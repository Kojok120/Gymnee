// API・MCP・LINE が共有する「やること」。入口が違っても同じ規則で読み書きする。
// ここでは認証済みの利用者 id だけを受け取り、権限（スコープ）の確認は入口側で済ませておく。

import type { Repo } from "./db/repo.js";
import { workoutIds } from "./domain/ids.js";
import { detectWorkoutPRs, estimate1RM, prLabel } from "./domain/pr.js";
import { buildSummary, type Summary } from "./domain/summary.js";
import { addDays } from "./domain/time.js";
import { normalizeName } from "./domain/exerciseMatch.js";
import { resolveWorkout, type LogWorkoutInput, type ResolveProblem } from "./domain/workoutInput.js";
import { muscleLabel, setVolume, type ExerciseInfo, type WorkoutRecord } from "./domain/types.js";
import { bossName } from "./domain/party.js";

/** 要約に使う記録の範囲。連続週を数えるのに足りる長さにする。 */
const SUMMARY_LOOKBACK_DAYS = 120;

export interface SummaryResult extends Summary {
  recentPersonalRecords: { exercise: string; type: string; label: string; value: number; achievedAt: string }[];
}

export type LogWorkoutResult =
  | {
      ok: true;
      workoutId: string;
      created: boolean;
      name: string;
      completedAt: string;
      exercises: { name: string; sets: number }[];
      personalRecords: { exercise: string; label: string; value: number }[];
    }
  | { ok: false; problems: ResolveProblem[] };

export interface MenuProposalInput {
  title: string;
  message: string;
  exercises: { name: string; sets: number; reps: number; weightKg: number }[];
}

export class GymneeService {
  constructor(
    private readonly repo: Repo,
    private readonly clock: () => Date = () => new Date(),
  ) {}

  async profile(userId: string) {
    const [profile, weeklyGoal] = await Promise.all([this.repo.profile(userId), this.repo.weeklyGoal(userId)]);
    return { id: userId, displayName: profile?.displayName ?? "ゲスト", weeklyGoal, timeZone: "Asia/Tokyo" };
  }

  async summary(userId: string): Promise<SummaryResult> {
    const now = this.clock();
    const [workouts, weeklyGoal, records] = await Promise.all([
      this.repo.completedWorkouts(userId, { from: addDays(now, -SUMMARY_LOOKBACK_DAYS), limit: 500 }),
      this.repo.weeklyGoal(userId),
      this.repo.personalRecords(userId),
    ]);
    return {
      ...buildSummary(workouts, weeklyGoal, now),
      recentPersonalRecords: records.slice(0, 5).map((r) => ({
        exercise: r.exerciseName ?? "種目",
        type: r.type,
        label: prLabel(r.type),
        value: Math.round(r.value * 10) / 10,
        achievedAt: r.achievedAt,
      })),
    };
  }

  listWorkouts(userId: string, options: { from?: Date; to?: Date; limit?: number }): Promise<WorkoutRecord[]> {
    return this.repo.completedWorkouts(userId, { ...options, limit: Math.min(options.limit ?? 20, 50) });
  }

  getWorkout(userId: string, workoutId: string): Promise<WorkoutRecord | null> {
    return this.repo.workout(userId, workoutId);
  }

  async listExercises(userId: string, query?: string): Promise<ExerciseInfo[]> {
    const all = await this.repo.exercises(userId);
    if (!query) return all;
    const key = normalizeName(query);
    return all.filter((e) => normalizeName(e.name).includes(key) || muscleLabel(e.muscleGroup) === query);
  }

  /** 種目ごとの履歴。1 回の記録につき、いちばん良かったセットと合計量を返す。 */
  async exerciseHistory(userId: string, exerciseId: string, limit = 20) {
    const [exercises, rows] = await Promise.all([this.repo.exercises(userId), this.repo.setsForExercises(userId, [exerciseId])]);
    const exercise = exercises.find((e) => e.id === exerciseId) ?? null;
    const byWorkout = new Map<string, { completedAt: string; sets: typeof rows }>();
    for (const row of rows) {
      const entry = byWorkout.get(row.workoutId) ?? { completedAt: row.completedAt, sets: [] };
      entry.sets.push(row);
      byWorkout.set(row.workoutId, entry);
    }
    const sessions = [...byWorkout.entries()]
      .sort((a, b) => b[1].completedAt.localeCompare(a[1].completedAt))
      .slice(0, Math.min(limit, 50))
      .map(([workoutId, { completedAt, sets }]) => {
        const records = sets.map((s) => ({
          index: s.set.set_index,
          weightKg: s.set.weight,
          reps: s.set.reps,
          durationSeconds: s.set.duration_seconds,
          distanceKm: s.set.distance_km,
          isPR: s.set.is_pr,
        }));
        const best = records.reduce<(typeof records)[number] | null>(
          (acc, s) => (acc === null || estimate1RM(s.weightKg, s.reps) > estimate1RM(acc.weightKg, acc.reps) ? s : acc),
          null,
        );
        return {
          workoutId,
          completedAt,
          sets: records.sort((a, b) => a.index - b.index),
          bestEst1RM: best ? Math.round(estimate1RM(best.weightKg, best.reps) * 10) / 10 : 0,
          volumeKg: Math.round(records.reduce((sum, s) => sum + setVolume(s), 0)),
        };
      });
    return { exercise, sessions };
  }

  async personalRecords(userId: string) {
    const rows = await this.repo.personalRecords(userId);
    return rows.map((r) => ({ ...r, label: prLabel(r.type), value: Math.round(r.value * 10) / 10 }));
  }

  bodyMetrics(userId: string, options: { from?: Date; to?: Date; limit?: number }) {
    return this.repo.bodyMetrics(userId, options);
  }

  async party(userId: string) {
    const parties = await this.repo.partyOverview(userId, this.clock());
    return parties.map((p) => ({
      partyId: p.party_id,
      name: p.name ?? "パーティ",
      weekStart: p.week_start,
      boss: { id: p.boss_id, name: bossName(p.boss_id) },
      hp: p.hp,
      damage: p.damage,
      remainingHp: Math.max(0, p.hp - p.damage),
      defeated: p.defeated,
      memberCount: p.member_count,
      myHits: p.my_hits,
      myWeeklyGoal: p.my_weekly_goal,
    }));
  }

  /**
   * 記録を足す。種目の照合 → 値の検証 → 自己ベストの判定 → 1 トランザクションで書き込み。
   * idempotencyKey が同じなら 2 回目は何も増やさず、1 回目の id を返す。
   */
  async logWorkout(userId: string, input: LogWorkoutInput, idempotencyKey?: string): Promise<LogWorkoutResult> {
    const now = this.clock();
    const catalog = await this.repo.exercises(userId);
    const resolved = resolveWorkout(input, catalog, now);
    if (!resolved.ok) return resolved;
    const w = resolved.workout;

    const history = await this.repo.setsForExercises(
      userId,
      w.exercises.map((e) => e.exercise.id),
    );
    const ids = await workoutIds(
      userId,
      idempotencyKey,
      w.exercises.map((e) => e.sets.length),
    );

    const personalRecords: { exercise_id: string; type: string; value: number }[] = [];
    const prSummary: { exercise: string; label: string; value: number }[] = [];
    const exercises = w.exercises.map((item, i) => {
      const past = history
        .filter((h) => h.exerciseId === item.exercise.id && h.completedAt <= w.completedAt.toISOString())
        .map((h) => ({ weightKg: h.set.weight, reps: h.set.reps, durationSeconds: h.set.duration_seconds }));
      const { perSet, records } = detectWorkoutPRs(item.exercise.measurementType, item.exercise.loadMode, past, item.sets);
      for (const pr of records) {
        personalRecords.push({ exercise_id: item.exercise.id, type: pr.type, value: pr.value });
        prSummary.push({ exercise: item.exercise.name, label: prLabel(pr.type), value: round1(pr.value) });
      }
      return {
        id: ids.exerciseIds[i],
        exercise_id: item.exercise.id,
        sets: item.sets.map((s, j) => ({
          id: ids.setIds[i]![j],
          set_index: j,
          weight: s.weightKg,
          reps: s.reps,
          duration_seconds: s.durationSeconds,
          distance_km: s.distanceKm,
          is_pr: perSet[j] ?? false,
        })),
      };
    });

    const result = await this.repo.logWorkout(userId, {
      id: ids.workoutId,
      name: w.name,
      date: w.date.toISOString(),
      completed_at: w.completedAt.toISOString(),
      duration_seconds: w.durationSeconds,
      note: w.note,
      exercises,
      personal_records: personalRecords,
    });

    return {
      ok: true,
      workoutId: result.workout_id,
      created: result.created,
      name: w.name,
      completedAt: w.completedAt.toISOString(),
      exercises: w.exercises.map((e) => ({ name: e.exercise.name, sets: e.sets.length })),
      // 再送（created=false）のときは今回の判定は書き込まれていないので、自己ベストは返さない。
      personalRecords: result.created ? prSummary : [],
    };
  }

  /** アプリのコーチ画面にメニューを提案する。取り込むかは利用者がアプリで決める。 */
  async proposeMenu(userId: string, input: MenuProposalInput, channel: "line" | "mcp" | "api" = "mcp") {
    const proposal = {
      title: input.title.slice(0, 40) || "今日のメニュー",
      exercises: input.exercises.slice(0, 8).map((e) => ({
        name: e.name.slice(0, 60),
        sets: clampInt(e.sets, 1, 10),
        reps: clampInt(e.reps, 1, 50),
        weightKg: clampInt(e.weightKg, 0, 500),
      })),
    };
    const { id } = await this.repo.addCoachMessage(userId, { body: input.message, isFromCoach: true, proposal, channel });
    return { messageId: id, proposal };
  }
}

function clampInt(v: number, min: number, max: number): number {
  return Number.isFinite(v) ? Math.max(min, Math.min(max, Math.round(v))) : min;
}

function round1(v: number): number {
  return Math.round(v * 10) / 10;
}

