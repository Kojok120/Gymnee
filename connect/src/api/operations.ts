// API の操作の一覧。ここが唯一の定義で、REST（/v1）・MCP の道具・OpenAPI はすべてここから作る。
// 操作を足すときはここに 1 件足すだけにする（ドキュメントと MCP がずれないようにするため。#171）。

import { z } from "zod";
import type { Scope } from "../domain/scopes.js";
import { LogWorkoutInput } from "../domain/workoutInput.js";
import type { GymneeService } from "../service.js";

export interface OperationContext {
  userId: string;
  service: GymneeService;
  /** 記録の追加の再送を見分ける鍵（REST は Idempotency-Key ヘッダー、MCP は引数）。 */
  idempotencyKey?: string;
}

export interface Operation {
  /** operationId。MCP の道具名にもそのまま使う（snake_case）。 */
  id: string;
  method: "GET" | "POST";
  /** OpenAPI の書き方（/v1/workouts/{workoutId}）。 */
  path: string;
  scope: Scope;
  title: string;
  description: string;
  input: z.ZodObject;
  /** 返り値の形（OpenAPI の説明用）。 */
  output: z.ZodType;
  /** 読むだけの操作か（MCP の readOnlyHint）。 */
  readOnly: boolean;
  /** 同じ入力で 2 回呼んでも結果が増えないか（MCP の idempotentHint）。 */
  idempotent: boolean;
  run(ctx: OperationContext, input: Record<string, unknown>): Promise<unknown>;
}

// ---- 共通の形 ----

const isoDate = z
  .string()
  .refine((s) => !Number.isNaN(Date.parse(s)), { message: "日付か日時（ISO 8601）で書く" })
  .describe("日付（2026-11-01）か日時（2026-11-01T09:00:00+09:00）");

const ExerciseSchema = z.object({
  id: z.string(),
  name: z.string(),
  muscleGroup: z.string().describe("部位（chest / back / shoulders / arms / abs / core / glutes / legs / cardio / full_body / other）"),
  equipment: z.string(),
  measurementType: z.enum(["weight", "bodyweight", "time", "cardio"]).describe("記録のしかた"),
  loadMode: z.enum(["none", "weighted", "assisted"]).describe("自重種目の負荷（自重のみ / 荷重 / 補助）"),
  isCustom: z.boolean().describe("自分で作った種目か"),
});

const SetSchema = z.object({
  index: z.number(),
  weightKg: z.number().describe("重量（kg）。補助付きの自重種目は負"),
  reps: z.number(),
  durationSeconds: z.number().nullable(),
  distanceKm: z.number().nullable(),
  isPR: z.boolean().describe("このセットで自己ベストを更新したか"),
});

const WorkoutSchema = z.object({
  id: z.string(),
  name: z.string(),
  date: z.string(),
  completedAt: z.string(),
  durationSeconds: z.number().nullable(),
  note: z.string().nullable(),
  exercises: z.array(z.object({ exercise: ExerciseSchema.nullable(), sets: z.array(SetSchema) })),
});

const WeekTotalsSchema = z.object({
  workouts: z.number(),
  activeDays: z.number(),
  sets: z.number(),
  volumeKg: z.number(),
  muscles: z.array(z.object({ label: z.string(), sets: z.number() })),
});

const SummarySchema = z.object({
  asOf: z.string(),
  weekStart: z.string().describe("今週の初日（JST・月曜始まり）"),
  weeklyGoal: z.number(),
  thisWeek: WeekTotalsSchema,
  lastWeek: WeekTotalsSchema,
  streakWeeks: z.number().describe("週の目標を続けて満たした週の数"),
  recordedToday: z.boolean(),
  daysSinceLastWorkout: z.number().nullable(),
  recentSessions: z.array(
    z.object({
      id: z.string(),
      name: z.string(),
      completedAt: z.string(),
      daysAgo: z.number(),
      sets: z.number(),
      volumeKg: z.number(),
      muscles: z.array(z.string()),
    }),
  ),
  recentPersonalRecords: z.array(
    z.object({ exercise: z.string(), type: z.string(), label: z.string(), value: z.number(), achievedAt: z.string() }),
  ),
});

const MenuExercise = z
  .object({
    name: z.string().min(1).max(60).describe("種目名（例: ベンチプレス）"),
    sets: z.number().int().min(1).max(10),
    reps: z.number().int().min(1).max(50),
    weightKg: z.number().min(0).max(500).describe("重量（kg）。自重なら 0"),
  })
  .strict();

function dateOrUndefined(v: unknown): Date | undefined {
  return typeof v === "string" ? new Date(v) : undefined;
}

// ---- 操作 ----

export const operations: Operation[] = [
  {
    id: "get_profile",
    method: "GET",
    path: "/v1/me",
    scope: "read",
    title: "自分の情報",
    description: "表示名・週の目標（回数）・タイムゾーンを返す。",
    input: z.object({}),
    output: z.object({ id: z.string(), displayName: z.string(), weeklyGoal: z.number(), timeZone: z.string() }),
    readOnly: true,
    idempotent: true,
    run: (ctx) => ctx.service.profile(ctx.userId),
  },
  {
    id: "get_summary",
    method: "GET",
    path: "/v1/summary",
    scope: "read",
    title: "いまの状況のまとめ",
    description:
      "今週と先週の回数・セット数・総量・部位、週の目標を続けて満たした週の数、最後に記録してからの日数、直近の記録と自己ベストをまとめて返す。ふりかえりやメニューを考える前に、まずこれを読む。週は JST の月曜始まり。",
    input: z.object({}),
    output: SummarySchema,
    readOnly: true,
    idempotent: true,
    run: (ctx) => ctx.service.summary(ctx.userId),
  },
  {
    id: "list_workouts",
    method: "GET",
    path: "/v1/workouts",
    scope: "read",
    title: "記録の一覧",
    description: "完了した記録を新しい順に返す。種目とセットの中身つき。from / to で期間を絞れる（to は含まない）。",
    input: z.object({
      from: isoDate.optional(),
      to: isoDate.optional(),
      limit: z.coerce.number().int().min(1).max(50).optional().describe("件数（1〜50、既定 20）"),
    }),
    output: z.array(WorkoutSchema),
    readOnly: true,
    idempotent: true,
    run: (ctx, input) =>
      ctx.service.listWorkouts(ctx.userId, {
        from: dateOrUndefined(input.from),
        to: dateOrUndefined(input.to),
        limit: input.limit as number | undefined,
      }),
  },
  {
    id: "get_workout",
    method: "GET",
    path: "/v1/workouts/{workoutId}",
    scope: "read",
    title: "記録を 1 件",
    description: "記録 1 件を、種目とセットの中身つきで返す。",
    input: z.object({ workoutId: z.uuid() }),
    output: WorkoutSchema,
    readOnly: true,
    idempotent: true,
    run: async (ctx, input) => {
      const w = await ctx.service.getWorkout(ctx.userId, input.workoutId as string);
      if (!w) throw new OperationError(404, "not_found", "その記録は見つからない");
      return w;
    },
  },
  {
    id: "log_workout",
    method: "POST",
    path: "/v1/workouts",
    scope: "workouts:write",
    title: "記録を足す",
    description:
      "終えたワークアウトを記録する。種目は Gymnee の種目に合わせる（名前か id。名前が一つに決まらないときは候補を返すので、選び直して呼び直す）。自己ベストはアプリと同じ規則で判定する。記録はアプリを開くと同期される。消す・直すはアプリで行う。" +
      "同じ記録を二重に足さないよう、REST では Idempotency-Key ヘッダー、MCP では idempotencyKey を付けることを勧める。",
    input: LogWorkoutInput.extend({
      idempotencyKey: z.string().min(8).max(100).optional().describe("再送で二重にならないための鍵（MCP 用。REST はヘッダー）"),
    }),
    output: z.object({
      workoutId: z.string(),
      created: z.boolean().describe("false なら同じ鍵で既に記録済み（何も増やしていない）"),
      name: z.string(),
      completedAt: z.string(),
      exercises: z.array(z.object({ name: z.string(), sets: z.number() })),
      personalRecords: z.array(z.object({ exercise: z.string(), label: z.string(), value: z.number() })),
    }),
    readOnly: false,
    idempotent: true,
    run: async (ctx, input) => {
      const { idempotencyKey, ...body } = input as LogWorkoutInput & { idempotencyKey?: string };
      const result = await ctx.service.logWorkout(ctx.userId, body, ctx.idempotencyKey ?? idempotencyKey);
      if (!result.ok) throw new OperationError(422, "unresolved", "記録の中身を確かめて", result.problems);
      return result;
    },
  },
  {
    id: "list_exercises",
    method: "GET",
    path: "/v1/exercises",
    scope: "read",
    title: "種目の一覧",
    description: "記録に使える種目（プリセットと自分の種目）。q で名前の一部か部位名（胸・背中・脚 など）で絞れる。",
    input: z.object({ q: z.string().max(40).optional().describe("名前の一部か部位名") }),
    output: z.array(ExerciseSchema),
    readOnly: true,
    idempotent: true,
    run: (ctx, input) => ctx.service.listExercises(ctx.userId, input.q as string | undefined),
  },
  {
    id: "get_exercise_history",
    method: "GET",
    path: "/v1/exercises/{exerciseId}/history",
    scope: "read",
    title: "種目の履歴",
    description: "ある種目の過去の記録を新しい順に返す。1 回ごとのセット・いちばん良かったセットの推定 1RM・総量つき。伸びや停滞を見るのに使う。",
    input: z.object({
      exerciseId: z.uuid(),
      limit: z.coerce.number().int().min(1).max(50).optional().describe("回数（既定 20）"),
    }),
    output: z.object({
      exercise: ExerciseSchema.nullable(),
      sessions: z.array(
        z.object({
          workoutId: z.string(),
          completedAt: z.string(),
          sets: z.array(SetSchema),
          bestEst1RM: z.number(),
          volumeKg: z.number(),
        }),
      ),
    }),
    readOnly: true,
    idempotent: true,
    run: (ctx, input) => ctx.service.exerciseHistory(ctx.userId, input.exerciseId as string, (input.limit as number | undefined) ?? 20),
  },
  {
    id: "list_personal_records",
    method: "GET",
    path: "/v1/personal-records",
    scope: "read",
    title: "自己ベスト",
    description: "種目ごと・種別ごと（最大重量・推定1RM・最大レップ・最長時間・最小補助）の自己ベストを、新しい順に返す。",
    input: z.object({}),
    output: z.array(
      z.object({
        exerciseId: z.string().nullable(),
        exerciseName: z.string().nullable(),
        type: z.string(),
        label: z.string(),
        value: z.number(),
        achievedAt: z.string(),
        workoutId: z.string().nullable(),
      }),
    ),
    readOnly: true,
    idempotent: true,
    run: (ctx) => ctx.service.personalRecords(ctx.userId),
  },
  {
    id: "list_body_metrics",
    method: "GET",
    path: "/v1/body-metrics",
    scope: "read",
    title: "体重・体脂肪率",
    description: "アプリで記録した体重と体脂肪率を新しい順に返す。ヘルスケア（HealthKit）から取り込んだ値は返さない。",
    input: z.object({
      from: isoDate.optional(),
      to: isoDate.optional(),
      limit: z.coerce.number().int().min(1).max(500).optional().describe("件数（既定 90）"),
    }),
    output: z.array(z.object({ date: z.string(), weightKg: z.number().nullable(), bodyFatPercent: z.number().nullable() })),
    readOnly: true,
    idempotent: true,
    run: (ctx, input) =>
      ctx.service.bodyMetrics(ctx.userId, {
        from: dateOrUndefined(input.from),
        to: dateOrUndefined(input.to),
        limit: input.limit as number | undefined,
      }),
  },
  {
    id: "get_party",
    method: "GET",
    path: "/v1/party",
    scope: "read",
    title: "パーティと週ボス",
    description: "入っているパーティごとに、今週のボス・HP・与えたダメージ・自分の回数を返す。ほかのメンバーの名前や回数は返さない。",
    input: z.object({}),
    output: z.array(
      z.object({
        partyId: z.string(),
        name: z.string(),
        weekStart: z.string(),
        boss: z.object({ id: z.string(), name: z.string() }),
        hp: z.number(),
        damage: z.number(),
        remainingHp: z.number(),
        defeated: z.boolean(),
        memberCount: z.number(),
        myHits: z.number(),
        myWeeklyGoal: z.number(),
      }),
    ),
    readOnly: true,
    idempotent: true,
    run: (ctx) => ctx.service.party(ctx.userId),
  },
  {
    id: "propose_menu",
    method: "POST",
    path: "/v1/coach/proposals",
    scope: "coach:write",
    title: "メニューを提案する",
    description:
      "アプリのコーチ画面に、メッセージとメニューの提案を届ける。利用者がアプリで「取り込む」を押すと、その日の計画になる。アプリの計画を直接書き換えることはしない。重量は直近の記録から地続きの範囲にする。",
    input: z.object({
      title: z.string().min(1).max(40).describe("メニュー名（例: 胸と三頭）"),
      message: z.string().min(1).max(500).describe("コーチからのひと言（1〜3 文）"),
      exercises: z.array(MenuExercise).min(1).max(8),
    }),
    output: z.object({
      messageId: z.string(),
      proposal: z.object({ title: z.string(), exercises: z.array(MenuExercise) }),
    }),
    readOnly: false,
    idempotent: false,
    run: (ctx, input) =>
      ctx.service.proposeMenu(ctx.userId, input as { title: string; message: string; exercises: z.infer<typeof MenuExercise>[] }),
  },
];

/** 操作が利用者の側の理由で失敗したとき（見つからない・中身が足りない）。 */
export class OperationError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
  }
}

export function findOperation(id: string): Operation | undefined {
  return operations.find((o) => o.id === id);
}
