import { describe, expect, it } from "vitest";
import { decryptString, encryptString, signState, verifyState, bytesToBase64 } from "../src/domain/crypto.js";
import { normalizeScopes, hasScopes, describeScopes } from "../src/domain/scopes.js";
import { buildSummary, streakWeeks } from "../src/domain/summary.js";
import { detectPR, detectWorkoutPRs, bestsFrom, estimate1RM, emptyBests } from "../src/domain/pr.js";
import { matchExercise, normalizeName } from "../src/domain/exerciseMatch.js";
import { resolveWorkout, LogWorkoutInput } from "../src/domain/workoutInput.js";
import { uuidV5, workoutIds } from "../src/domain/ids.js";
import { jstDay, jstWeekStart, jstHour } from "../src/domain/time.js";
import type { ExerciseInfo, WorkoutRecord } from "../src/domain/types.js";

const key = bytesToBase64(new Uint8Array(32).map((_, i) => i));

const bench: ExerciseInfo = { id: "11111111-1111-4111-8111-111111111111", name: "ベンチプレス", muscleGroup: "chest", equipment: "barbell", measurementType: "weight", loadMode: "none", isCustom: false };
const inclineBench: ExerciseInfo = { ...bench, id: "11111111-1111-4111-8111-111111111112", name: "インクラインベンチプレス" };
const pushup: ExerciseInfo = { id: "22222222-2222-4222-8222-222222222222", name: "腕立て伏せ", muscleGroup: "chest", equipment: "bodyweight", measurementType: "bodyweight", loadMode: "none", isCustom: false };
const pullupAssist: ExerciseInfo = { id: "33333333-3333-4333-8333-333333333333", name: "アシスト懸垂", muscleGroup: "back", equipment: "machine", measurementType: "bodyweight", loadMode: "assisted", isCustom: false };
const plank: ExerciseInfo = { id: "44444444-4444-4444-8444-444444444444", name: "プランク", muscleGroup: "core", equipment: "bodyweight", measurementType: "time", loadMode: "none", isCustom: false };
const catalog = [bench, inclineBench, pushup, pullupAssist, plank];

function workout(id: string, completedAt: string, sets = 3): WorkoutRecord {
  return {
    id, name: "胸の日", date: completedAt, completedAt, durationSeconds: null, note: null,
    exercises: [{ exercise: bench, sets: Array.from({ length: sets }, (_, i) => ({ index: i, weightKg: 60, reps: 10, durationSeconds: null, distanceKm: null, isPR: false })) }],
  };
}

describe("crypto", () => {
  it("暗号化して戻せる・毎回違う暗号文になる", async () => {
    const a = await encryptString(key, "https://hooks.slack.com/services/T/B/x");
    const b = await encryptString(key, "https://hooks.slack.com/services/T/B/x");
    expect(a).not.toBe(b);
    expect(await decryptString(key, a)).toBe("https://hooks.slack.com/services/T/B/x");
  });

  it("改ざんした暗号文は戻せない", async () => {
    const a = await encryptString(key, "secret");
    const broken = a.slice(0, -2) + (a.endsWith("A") ? "BB" : "AA");
    await expect(decryptString(key, broken)).rejects.toThrow();
  });

  it("署名付き state: 用途・期限・改ざんを確かめる", async () => {
    const now = 1_800_000_000;
    const token = await signState("s".repeat(32), { u: "user-1", k: "slack", exp: now + 600 });
    expect((await verifyState("s".repeat(32), token, "slack", now))?.u).toBe("user-1");
    expect(await verifyState("s".repeat(32), token, "discord", now)).toBeNull();
    expect(await verifyState("s".repeat(32), token, "slack", now + 601)).toBeNull();
    expect(await verifyState("t".repeat(32), token, "slack", now)).toBeNull();
  });
});

describe("scopes", () => {
  it("read は必ず含め、知らない権限は落とす", () => {
    expect(normalizeScopes(["coach:write", "admin", "offline_access"])).toEqual(["read", "coach:write"]);
    expect(normalizeScopes([])).toEqual(["read"]);
  });
  it("足りるかを判定する", () => {
    expect(hasScopes(["read"], ["workouts:write"])).toBe(false);
    expect(hasScopes(["read", "workouts:write"], ["workouts:write"])).toBe(true);
    expect(describeScopes(["read"])[0]?.label).toContain("読む");
  });
});

describe("time (JST)", () => {
  it("UTC の夜は JST の翌日", () => {
    expect(jstDay(new Date("2026-11-04T16:30:00Z"))).toBe("2026-11-05");
    expect(jstHour(new Date("2026-11-04T22:00:00Z"))).toBe(7);
  });
  it("週は JST の月曜 0 時から", () => {
    // 2026-11-08 は日曜。その週の月曜は 11-02。
    expect(jstWeekStart(new Date("2026-11-08T14:00:00Z")).toISOString()).toBe("2026-11-01T15:00:00.000Z");
  });
});

describe("summary", () => {
  const now = new Date("2026-11-05T12:00:00+09:00"); // 木曜
  it("今週・先週・連続週・最後の記録", () => {
    const workouts = [
      workout("w1", "2026-11-03T19:00:00+09:00"),
      workout("w2", "2026-11-05T07:00:00+09:00"),
      workout("w3", "2026-10-27T19:00:00+09:00"),
      workout("w4", "2026-10-28T19:00:00+09:00"),
      workout("w5", "2026-10-30T19:00:00+09:00"),
    ];
    const s = buildSummary(workouts, 3, now);
    expect(s.thisWeek.workouts).toBe(2);
    expect(s.thisWeek.sets).toBe(6);
    expect(s.thisWeek.volumeKg).toBe(3600);
    expect(s.thisWeek.muscles).toEqual([{ label: "胸", sets: 6 }]);
    expect(s.lastWeek.workouts).toBe(3);
    // 今週は未達（2/3）なので先週から数える: 先週 3 回で達成、その前は 0 回。
    expect(s.streakWeeks).toBe(1);
    expect(s.recordedToday).toBe(true);
    expect(s.daysSinceLastWorkout).toBe(0);
    expect(s.recentSessions[0]?.id).toBe("w2");
  });
  it("記録が無ければ空", () => {
    const s = buildSummary([], 3, now);
    expect(s.daysSinceLastWorkout).toBeNull();
    expect(s.streakWeeks).toBe(0);
  });
  it("今週が達成済みなら今週から数える", () => {
    const ws = ["2026-11-02", "2026-11-03", "2026-11-04", "2026-10-26", "2026-10-27"].map((d, i) => workout(`w${i}`, `${d}T19:00:00+09:00`));
    expect(streakWeeks(ws, 2, now)).toBe(2);
  });
});

describe("pr（アプリの PRDetector と同じ規則）", () => {
  it("推定 1RM は Epley、1 回は重量そのもの", () => {
    expect(estimate1RM(100, 1)).toBe(100);
    expect(estimate1RM(60, 10)).toBeCloseTo(80);
    expect(estimate1RM(0, 10)).toBe(0);
  });
  it("重量種目: 最大重量と推定 1RM", () => {
    const b = bestsFrom([{ weightKg: 60, reps: 10, durationSeconds: null }]);
    expect(detectPR("weight", "none", { weightKg: 62.5, reps: 5, durationSeconds: null }, b).map((p) => p.type)).toEqual(["max_weight"]);
    expect(detectPR("weight", "none", { weightKg: 60, reps: 12, durationSeconds: null }, b).map((p) => p.type)).toEqual(["est_1rm"]);
  });
  it("自重のみ: 最大レップ", () => {
    expect(detectPR("bodyweight", "none", { weightKg: 0, reps: 20, durationSeconds: null }, bestsFrom([{ weightKg: 0, reps: 15, durationSeconds: null }]))).toEqual([{ type: "max_reps", value: 20 }]);
  });
  it("補助: 軽い補助で更新、履歴なしの自重は PR にしない", () => {
    const b = bestsFrom([{ weightKg: -20, reps: 8, durationSeconds: null }]);
    expect(detectPR("bodyweight", "assisted", { weightKg: -10, reps: 8, durationSeconds: null }, b)).toEqual([{ type: "min_assist", value: 10 }]);
    expect(detectPR("bodyweight", "assisted", { weightKg: 0, reps: 5, durationSeconds: null }, emptyBests())).toEqual([]);
  });
  it("時間: 最長時間。有酸素は対象外", () => {
    expect(detectPR("time", "none", { weightKg: 0, reps: 0, durationSeconds: 90 }, bestsFrom([{ weightKg: 0, reps: 0, durationSeconds: 60 }]))).toEqual([{ type: "max_duration", value: 90 }]);
    expect(detectPR("cardio", "none", { weightKg: 0, reps: 0, durationSeconds: 999 }, emptyBests())).toEqual([]);
  });
  it("1 回の中で順に更新したら、種別ごとに最大だけ残す", () => {
    const r = detectWorkoutPRs("weight", "none", [{ weightKg: 60, reps: 10, durationSeconds: null }], [
      { weightKg: 62.5, reps: 8, durationSeconds: null },
      { weightKg: 65, reps: 5, durationSeconds: null },
      { weightKg: 50, reps: 10, durationSeconds: null },
    ]);
    expect(r.perSet).toEqual([true, true, false]);
    expect(r.records.find((x) => x.type === "max_weight")?.value).toBe(65);
  });
});

describe("exerciseMatch", () => {
  it("表記ゆれを畳む", () => {
    expect(normalizeName("ﾍﾞﾝﾁ プレス")).toBe(normalizeName("ベンチプレス"));
    expect(normalizeName("うでたてふせ")).toBe(normalizeName("ウデタテフセ"));
  });
  it("完全一致・含む 1 件は決まる。2 件以上は候補", () => {
    expect(matchExercise("ベンチプレス", catalog)).toMatchObject({ kind: "matched", exercise: { id: bench.id } });
    expect(matchExercise("プランク", catalog)).toMatchObject({ kind: "matched" });
    const amb = matchExercise("ベンチ", catalog);
    expect(amb.kind).toBe("ambiguous");
    expect(amb.kind !== "matched" && amb.candidates.map((c) => c.name)).toContain("ベンチプレス");
    expect(matchExercise("スクワット", catalog).kind).toBe("unknown");
  });
  it("自分の種目を優先する", () => {
    const mine = { ...bench, id: "99999999-9999-4999-8999-999999999999", isCustom: true };
    expect(matchExercise("ベンチプレス", [bench, mine])).toMatchObject({ kind: "matched", exercise: { id: mine.id } });
  });
});

describe("workoutInput", () => {
  const now = new Date("2026-11-05T12:00:00+09:00");
  it("名前で種目を決め、同じ種目はまとめる", () => {
    const input = LogWorkoutInput.parse({
      name: "胸",
      durationMinutes: 45,
      exercises: [
        { name: "ベンチプレス", sets: [{ weightKg: 60, reps: 10 }] },
        { exerciseId: bench.id, sets: [{ weightKg: 62.5, reps: 8 }] },
        { name: "腕立て伏せ", sets: [{ reps: 20 }] },
      ],
    });
    const r = resolveWorkout(input, catalog, now);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.workout.exercises).toHaveLength(2);
    expect(r.workout.exercises[0]?.sets).toHaveLength(2);
    expect(r.workout.durationSeconds).toBe(2700);
    expect(r.workout.date.getTime()).toBe(now.getTime() - 2700 * 1000);
  });
  it("計測タイプに合わない値と、決まらない種目は理由と候補を返す", () => {
    const input = LogWorkoutInput.parse({
      exercises: [
        { name: "ベンチ", sets: [{ weightKg: 60, reps: 10 }] },
        { name: "プランク", sets: [{ reps: 10 }] },
        { exerciseId: bench.id, sets: [{ reps: 10 }] },
      ],
    });
    const r = resolveWorkout(input, catalog, now);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.problems.map((p) => p.exerciseIndex)).toEqual([0, 1, 2]);
    expect(r.problems[0]?.candidates?.length).toBeGreaterThan(0);
  });
  it("未来と 1 年より前は断る", () => {
    const future = LogWorkoutInput.parse({ completedAt: "2026-11-06T12:00:00+09:00", exercises: [{ name: "プランク", sets: [{ durationSeconds: 60 }] }] });
    expect(resolveWorkout(future, catalog, now).ok).toBe(false);
    const old = LogWorkoutInput.parse({ completedAt: "2025-10-01T12:00:00+09:00", exercises: [{ name: "プランク", sets: [{ durationSeconds: 60 }] }] });
    expect(resolveWorkout(old, catalog, now).ok).toBe(false);
  });
  it("知らない項目は受け付けない", () => {
    expect(LogWorkoutInput.safeParse({ exercises: [], userId: "x" }).success).toBe(false);
  });
});

describe("ids", () => {
  it("UUID v5 は RFC の例と一致する", async () => {
    // RFC 4122 付録の DNS 名前空間の例（python: uuid.uuid5(uuid.NAMESPACE_DNS, "www.example.com")）
    expect(await uuidV5("www.example.com", "6ba7b810-9dad-11d1-80b4-00c04fd430c8")).toBe("2ed6657d-e927-568b-95e1-2665a8aea6a2");
  });
  it("同じ鍵なら同じ id、鍵が無ければ毎回違う", async () => {
    const a = await workoutIds("u1", "key-12345", [2, 1]);
    const b = await workoutIds("u1", "key-12345", [2, 1]);
    const c = await workoutIds("u2", "key-12345", [2, 1]);
    expect(a).toEqual(b);
    expect(a.workoutId).not.toBe(c.workoutId);
    expect(a.setIds[0]).toHaveLength(2);
    const d = await workoutIds("u1", undefined, [1]);
    const e = await workoutIds("u1", undefined, [1]);
    expect(d.workoutId).not.toBe(e.workoutId);
  });
});
