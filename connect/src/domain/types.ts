// サーバー側で扱う記録の形。PostgREST の行（snake_case）から repo 層で変換して作る。
// アプリの SwiftData モデルと同じ意味の値だけを持つ。

export type MeasurementType = "weight" | "bodyweight" | "time" | "cardio";
export type LoadMode = "none" | "weighted" | "assisted";

export const MUSCLE_LABELS: Record<string, string> = {
  chest: "胸",
  back: "背中",
  shoulders: "肩",
  arms: "二頭・三頭",
  abs: "腹",
  core: "体幹",
  glutes: "臀部",
  legs: "脚",
  cardio: "有酸素",
  full_body: "全身",
  other: "その他",
};

export function muscleLabel(raw: string | null | undefined): string {
  return (raw && MUSCLE_LABELS[raw]) || "その他";
}

export interface ExerciseInfo {
  id: string;
  name: string;
  muscleGroup: string;
  equipment: string;
  measurementType: MeasurementType;
  loadMode: LoadMode;
  isCustom: boolean;
}

export interface SetRecord {
  index: number;
  /** kg。自重の補助は負の値（アプリの符号付き重量と同じ）。 */
  weightKg: number;
  reps: number;
  durationSeconds: number | null;
  distanceKm: number | null;
  isPR: boolean;
}

export interface WorkoutExerciseRecord {
  exercise: ExerciseInfo | null;
  sets: SetRecord[];
}

export interface WorkoutRecord {
  id: string;
  name: string;
  /** 記録の日付（開始）。 */
  date: string;
  /** 完了時刻。活動日はこれで決まる（アプリの Workout.completedAt と同じ）。 */
  completedAt: string;
  durationSeconds: number | null;
  note: string | null;
  exercises: WorkoutExerciseRecord[];
}

export interface PersonalRecordRow {
  exerciseId: string | null;
  exerciseName: string | null;
  type: string;
  value: number;
  achievedAt: string;
  workoutId: string | null;
}

/** セットの総量（kg × 回）。自重・時間・有酸素は 0。 */
export function setVolume(set: SetRecord): number {
  if (!(set.weightKg > 0) || !(set.reps > 0)) return 0;
  const v = set.weightKg * set.reps;
  return Number.isFinite(v) ? v : 0;
}
