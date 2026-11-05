// 外部から記録を足すときの入力と、その検証（純粋）。API・MCP・LINE が同じ規則を使う。
// 種目は既存のものにだけ合わせる。計測タイプに合わない値（重量種目なのに回数が無い等）は断る。

import { z } from "zod";
import { matchExercise } from "./exerciseMatch.js";
import type { ExerciseInfo } from "./types.js";

export const LogSetInput = z
  .object({
    weightKg: z.number().min(-300).max(1000).optional().describe("重量（kg）。補助付きの自重種目は負の値（-10 = 10kg の補助）"),
    reps: z.number().int().min(0).max(1000).optional().describe("回数"),
    durationSeconds: z.number().int().min(0).max(86_400).optional().describe("時間（秒）。プランクなど時間の種目と有酸素で使う"),
    distanceKm: z.number().min(0).max(1000).optional().describe("距離（km）。有酸素で使う"),
  })
  .strict();

export const LogExerciseInput = z
  .object({
    exerciseId: z.uuid().optional().describe("種目の id（list_exercises で取れる）。name とどちらかが要る"),
    name: z.string().min(1).max(60).optional().describe("種目名（例: ベンチプレス）。id が分からないとき"),
    sets: z.array(LogSetInput).min(1).max(30),
  })
  .strict()
  .refine((v) => v.exerciseId !== undefined || v.name !== undefined, { message: "exerciseId か name のどちらかが要る" });

export const LogWorkoutInput = z
  .object({
    name: z.string().min(1).max(60).optional().describe("記録の名前（例: 胸の日）。省略すると「ワークアウト」"),
    completedAt: z.iso.datetime({ offset: true }).optional().describe("終えた時刻（ISO 8601）。省略すると今"),
    durationMinutes: z.number().int().min(1).max(600).optional().describe("かかった時間（分）"),
    note: z.string().max(1000).optional().describe("メモ"),
    exercises: z.array(LogExerciseInput).min(1).max(20),
  })
  .strict();

export type LogWorkoutInput = z.infer<typeof LogWorkoutInput>;
export type LogSetInput = z.infer<typeof LogSetInput>;

export interface ResolvedSet {
  weightKg: number;
  reps: number;
  durationSeconds: number | null;
  distanceKm: number | null;
}

export interface ResolvedWorkout {
  name: string;
  date: Date;
  completedAt: Date;
  durationSeconds: number | null;
  note: string | null;
  exercises: { exercise: ExerciseInfo; sets: ResolvedSet[] }[];
}

export interface ResolveProblem {
  /** 入力の何番目の種目か（0 始まり）。 */
  exerciseIndex: number;
  message: string;
  /** 種目が決まらなかったときの候補（名前で選び直してもらう）。 */
  candidates?: { id: string; name: string }[];
}

export type ResolveResult = { ok: true; workout: ResolvedWorkout } | { ok: false; problems: ResolveProblem[] };

/** 過去の記録として足せる範囲。古い記録の取り込みも許すが、1 年より前は断る。 */
const MAX_BACKFILL_DAYS = 365;
/** 端末の時計のずれを見込んで、少しだけ未来を許す。 */
const FUTURE_TOLERANCE_MS = 5 * 60 * 1000;

function checkSet(exercise: ExerciseInfo, s: LogSetInput): string | null {
  const weight = s.weightKg ?? 0;
  const reps = s.reps ?? 0;
  switch (exercise.measurementType) {
    case "weight":
      if (!(weight > 0) || reps < 1) return `${exercise.name} は重量（kg）と回数が要る`;
      return null;
    case "bodyweight":
      if (reps < 1) return `${exercise.name} は回数が要る`;
      if (exercise.loadMode === "none" && weight !== 0) return `${exercise.name} は自重のみの種目なので重量は付けない`;
      return null;
    case "time":
      if (!((s.durationSeconds ?? 0) > 0)) return `${exercise.name} は時間（秒）が要る`;
      return null;
    case "cardio":
      if (!((s.durationSeconds ?? 0) > 0) && !((s.distanceKm ?? 0) > 0)) return `${exercise.name} は時間か距離が要る`;
      return null;
  }
}

export function resolveWorkout(input: LogWorkoutInput, catalog: readonly ExerciseInfo[], now: Date): ResolveResult {
  const problems: ResolveProblem[] = [];
  const completedAt = input.completedAt ? new Date(input.completedAt) : now;
  if (completedAt.getTime() > now.getTime() + FUTURE_TOLERANCE_MS) {
    problems.push({ exerciseIndex: -1, message: "未来の時刻では記録できない" });
  }
  if (completedAt.getTime() < now.getTime() - MAX_BACKFILL_DAYS * 86_400_000) {
    problems.push({ exerciseIndex: -1, message: `${MAX_BACKFILL_DAYS} 日より前の記録は足せない` });
  }

  const byId = new Map(catalog.map((e) => [e.id, e]));
  const exercises: ResolvedWorkout["exercises"] = [];
  input.exercises.forEach((item, index) => {
    let exercise: ExerciseInfo | undefined;
    if (item.exerciseId) {
      exercise = byId.get(item.exerciseId);
      if (!exercise) {
        problems.push({ exerciseIndex: index, message: "その id の種目は見つからない（list_exercises で確かめて）" });
        return;
      }
    } else {
      const match = matchExercise(item.name ?? "", catalog);
      if (match.kind !== "matched") {
        problems.push({
          exerciseIndex: index,
          message: `「${item.name}」に当たる種目が一つに決まらない`,
          candidates: match.candidates.map((c) => ({ id: c.id, name: c.name })),
        });
        return;
      }
      exercise = match.exercise;
    }
    for (const s of item.sets) {
      const bad = checkSet(exercise, s);
      if (bad) {
        problems.push({ exerciseIndex: index, message: bad });
        return;
      }
    }
    // 同じ種目が 2 回書かれていたら 1 つにまとめる（アプリでも 1 つの種目の行にセットが並ぶ）。
    const sets = item.sets.map((s) => ({
      weightKg: s.weightKg ?? 0,
      reps: s.reps ?? 0,
      durationSeconds: s.durationSeconds ?? null,
      distanceKm: s.distanceKm ?? null,
    }));
    const existing = exercises.find((e) => e.exercise.id === exercise!.id);
    if (existing) existing.sets.push(...sets);
    else exercises.push({ exercise, sets });
  });

  if (problems.length > 0) return { ok: false, problems };
  const durationSeconds = input.durationMinutes ? input.durationMinutes * 60 : null;
  return {
    ok: true,
    workout: {
      name: input.name?.trim() || "ワークアウト",
      date: durationSeconds ? new Date(completedAt.getTime() - durationSeconds * 1000) : completedAt,
      completedAt,
      durationSeconds,
      note: input.note?.trim() || null,
      exercises,
    },
  };
}
