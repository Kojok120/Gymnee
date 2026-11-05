// 記録から「いまの状況」の要約を作る（純粋計算）。API の summary・MCP・LINE のコーチ・週報が同じものを使う。
// アプリの CoachInputs.brief と同じ考え方で、何を根拠に話してよいかをここで確定させる。
// 名前・メール・写真など、個人を特定できる情報は含めない。

import { addDays, jstDay, jstDaysBetween, jstWeekStart } from "./time.js";
import { muscleLabel, setVolume, type WorkoutRecord } from "./types.js";

export const RECENT_SESSION_LIMIT = 8;
/** 連続週を数えるときに遡る上限（それ以上は数えない）。 */
const STREAK_LOOKBACK_WEEKS = 52;

export interface SessionSummary {
  id: string;
  name: string;
  completedAt: string;
  daysAgo: number;
  sets: number;
  volumeKg: number;
  muscles: string[];
}

export interface WeekTotals {
  workouts: number;
  activeDays: number;
  sets: number;
  volumeKg: number;
  /** 部位ごとのセット数（多い順）。 */
  muscles: { label: string; sets: number }[];
}

export interface Summary {
  asOf: string;
  /** 今週（JST・月曜始まり）の初日。 */
  weekStart: string;
  weeklyGoal: number;
  thisWeek: WeekTotals;
  lastWeek: WeekTotals;
  /** 週の目標を続けて満たした週の数。今週が未達なら先週から数える。 */
  streakWeeks: number;
  recordedToday: boolean;
  daysSinceLastWorkout: number | null;
  recentSessions: SessionSummary[];
}

function completedDate(w: WorkoutRecord): Date {
  return new Date(w.completedAt);
}

function sessionSummary(w: WorkoutRecord, now: Date): SessionSummary {
  let sets = 0;
  let volume = 0;
  const muscles = new Set<string>();
  for (const we of w.exercises) {
    if (we.exercise) muscles.add(muscleLabel(we.exercise.muscleGroup));
    for (const s of we.sets) {
      sets += 1;
      volume += setVolume(s);
    }
  }
  return {
    id: w.id,
    name: w.name,
    completedAt: w.completedAt,
    daysAgo: Math.max(0, jstDaysBetween(completedDate(w), now)),
    sets,
    volumeKg: Math.round(volume),
    muscles: [...muscles].sort(),
  };
}

export function weekTotals(workouts: WorkoutRecord[]): WeekTotals {
  const days = new Set<string>();
  const byMuscle = new Map<string, number>();
  let sets = 0;
  let volume = 0;
  for (const w of workouts) {
    days.add(jstDay(completedDate(w)));
    for (const we of w.exercises) {
      const label = muscleLabel(we.exercise?.muscleGroup);
      byMuscle.set(label, (byMuscle.get(label) ?? 0) + we.sets.length);
      for (const s of we.sets) {
        sets += 1;
        volume += setVolume(s);
      }
    }
  }
  return {
    workouts: workouts.length,
    activeDays: days.size,
    sets,
    volumeKg: Math.round(volume),
    muscles: [...byMuscle.entries()]
      .filter(([, n]) => n > 0)
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .map(([label, n]) => ({ label, sets: n })),
  };
}

/** その週（月曜 0 時から 7 日）に完了した記録。 */
export function workoutsInWeek(workouts: WorkoutRecord[], weekStart: Date): WorkoutRecord[] {
  const end = addDays(weekStart, 7);
  return workouts.filter((w) => {
    const t = completedDate(w).getTime();
    return t >= weekStart.getTime() && t < end.getTime();
  });
}

export function streakWeeks(workouts: WorkoutRecord[], weeklyGoal: number, now: Date): number {
  const goal = Math.max(1, Math.min(7, Math.round(weeklyGoal)));
  let cursor = jstWeekStart(now);
  // 今週はまだ途中なので、未達なら先週から数える。
  if (workoutsInWeek(workouts, cursor).length < goal) cursor = addDays(cursor, -7);
  let count = 0;
  for (let i = 0; i < STREAK_LOOKBACK_WEEKS; i++) {
    if (workoutsInWeek(workouts, cursor).length < goal) break;
    count += 1;
    cursor = addDays(cursor, -7);
  }
  return count;
}

export function buildSummary(workouts: WorkoutRecord[], weeklyGoal: number, now: Date): Summary {
  const completed = [...workouts].sort((a, b) => b.completedAt.localeCompare(a.completedAt));
  const weekStart = jstWeekStart(now);
  const last = completed[0];
  return {
    asOf: now.toISOString(),
    weekStart: weekStart.toISOString(),
    weeklyGoal,
    thisWeek: weekTotals(workoutsInWeek(completed, weekStart)),
    lastWeek: weekTotals(workoutsInWeek(completed, addDays(weekStart, -7))),
    streakWeeks: streakWeeks(completed, weeklyGoal, now),
    recordedToday: completed.some((w) => jstDay(completedDate(w)) === jstDay(now)),
    daysSinceLastWorkout: last ? Math.max(0, jstDaysBetween(completedDate(last), now)) : null,
    recentSessions: completed.slice(0, RECENT_SESSION_LIMIT).map((w) => sessionSummary(w, now)),
  };
}
