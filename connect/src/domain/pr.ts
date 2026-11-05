// 自己ベストの判定。アプリの PRDetector / OneRepMax / WorkoutMetrics.bests と同じ規則にそろえる。
// 外部（LINE・API・MCP）から足した記録でも、アプリで記録したときと同じ自己ベストが付くようにするため。
// 規則を変えるときは Swift 側（Gymnee/Core/Domain/PRDetector.swift）と同時に変える。

import type { LoadMode, MeasurementType } from "./types.js";

export type PRType = "max_weight" | "est_1rm" | "max_reps" | "max_duration" | "min_assist";

export interface Bests {
  maxWeight: number;
  est1RM: number;
  maxReps: number;
  maxDuration: number;
  /** 補助の最小（軽いほど強い）。未記録は Infinity。 */
  minAssist: number;
}

export interface CandidateSet {
  weightKg: number;
  reps: number;
  durationSeconds: number | null;
}

export interface DetectedPR {
  type: PRType;
  value: number;
}

export function emptyBests(): Bests {
  return { maxWeight: 0, est1RM: 0, maxReps: 0, maxDuration: 0, minAssist: Number.POSITIVE_INFINITY };
}

/** 推定 1RM（Epley）。1 回なら重量そのもの。 */
export function estimate1RM(weight: number, reps: number): number {
  if (!(weight > 0) || reps < 1) return 0;
  if (reps === 1) return weight;
  return weight * (1 + reps / 30);
}

/** 過去のセットから現在のベストを作る（WorkoutMetrics.bests と同じ）。 */
export function bestsFrom(sets: readonly CandidateSet[]): Bests {
  const b = emptyBests();
  for (const s of sets) {
    if (s.weightKg > 0 && s.reps > 0) {
      b.maxWeight = Math.max(b.maxWeight, s.weightKg);
      b.est1RM = Math.max(b.est1RM, estimate1RM(s.weightKg, s.reps));
    }
    if (s.reps > 0) {
      b.maxReps = Math.max(b.maxReps, s.reps);
      if (s.weightKg <= 0) b.minAssist = Math.min(b.minAssist, -s.weightKg);
    }
    if (s.durationSeconds && s.durationSeconds > 0) {
      b.maxDuration = Math.max(b.maxDuration, s.durationSeconds);
    }
  }
  return b;
}

/** 1 セットが更新した自己ベスト（PRDetector.detect と同じ）。 */
export function detectPR(
  measurementType: MeasurementType,
  loadMode: LoadMode,
  set: CandidateSet,
  bests: Bests,
): DetectedPR[] {
  const out: DetectedPR[] = [];
  switch (measurementType) {
    case "weight": {
      if (!(set.weightKg > 0) || set.reps < 1) return [];
      if (set.weightKg > bests.maxWeight) out.push({ type: "max_weight", value: set.weightKg });
      const est = estimate1RM(set.weightKg, set.reps);
      if (est > bests.est1RM) out.push({ type: "est_1rm", value: est });
      return out;
    }
    case "bodyweight": {
      if (set.reps < 1) return [];
      if (loadMode === "none") {
        if (set.reps > bests.maxReps) out.push({ type: "max_reps", value: set.reps });
        return out;
      }
      if (set.weightKg > 0) {
        if (set.weightKg > bests.maxWeight) out.push({ type: "max_weight", value: set.weightKg });
      } else if (set.weightKg < 0 || Number.isFinite(bests.minAssist)) {
        if (-set.weightKg < bests.minAssist) out.push({ type: "min_assist", value: -set.weightKg });
      }
      return out;
    }
    case "time": {
      const secs = set.durationSeconds ?? 0;
      if (!(secs > 0)) return [];
      if (secs > bests.maxDuration) out.push({ type: "max_duration", value: secs });
      return out;
    }
    case "cardio":
      return [];
  }
}

/** 1 回のワークアウトの中で、セットを順に見ていって更新した自己ベストを集める（同じ種別は最大値だけ残す）。 */
export function detectWorkoutPRs(
  measurementType: MeasurementType,
  loadMode: LoadMode,
  history: readonly CandidateSet[],
  newSets: readonly CandidateSet[],
): { perSet: boolean[]; records: DetectedPR[] } {
  const seen: CandidateSet[] = [...history];
  const best = new Map<PRType, number>();
  const perSet = newSets.map((s) => {
    const detected = detectPR(measurementType, loadMode, s, bestsFrom(seen));
    seen.push(s);
    for (const pr of detected) {
      const prev = best.get(pr.type);
      // min_assist は小さいほど強い。それ以外は大きいほど強い。
      const better = prev === undefined || (pr.type === "min_assist" ? pr.value < prev : pr.value > prev);
      if (better) best.set(pr.type, pr.value);
    }
    return detected.length > 0;
  });
  return { perSet, records: [...best.entries()].map(([type, value]) => ({ type, value })) };
}

export const PR_LABELS: Record<PRType, string> = {
  max_weight: "最大重量",
  est_1rm: "推定1RM",
  max_reps: "最大レップ",
  max_duration: "最長時間",
  min_assist: "最小補助",
};

export function prLabel(type: string): string {
  return (PR_LABELS as Record<string, string>)[type] ?? type;
}
