import { describe, expect, it } from "vitest";
import { verifyLineSignature, linkMessageUrl, type LineClient, type LineMessage } from "../src/integrations/line.js";
import { allowPush, decideNotice, reserveFor } from "../src/domain/lineNotify.js";
import { confirmLog, planToLogInput, weeklyReview } from "../src/domain/lineMessages.js";
import { parseCoachOutput } from "../src/domain/lineCoach.js";
import { handleLineEvents } from "../src/line/webhook.js";
import { runLineDaily } from "../src/jobs/lineDaily.js";
import { buildSummary, type Summary } from "../src/domain/summary.js";
import type { Env } from "../src/env.js";
import type { LineLinkRow, Repo } from "../src/db/repo.js";
import type { ExerciseInfo, WorkoutRecord } from "../src/domain/types.js";

const USER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const LINE_USER = "U" + "0".repeat(31) + "1";
const bench: ExerciseInfo = { id: "11111111-1111-4111-8111-111111111111", name: "ベンチプレス", muscleGroup: "chest", equipment: "barbell", measurementType: "weight", loadMode: "none", isCustom: false };
const incline: ExerciseInfo = { ...bench, id: "11111111-1111-4111-8111-111111111112", name: "インクラインベンチプレス" };
const NOW = new Date("2026-11-06T07:05:00+09:00");

const env = {
  PUBLIC_ORIGIN: "https://api.gymnee.app",
  SITE_ORIGIN: "https://gymnee.app",
  LINE_MESSAGING_CHANNEL_ID: "123",
  LINE_MESSAGING_CHANNEL_SECRET: "line-secret",
  LINE_BASIC_ID: "@gymnee",
  GEMINI_API_KEY: "g",
} as unknown as Env;

function summaryWith(daysSince: number | null, recordedToday = false): Summary {
  const s = buildSummary([], 3, NOW);
  return { ...s, daysSinceLastWorkout: daysSince, recordedToday };
}

describe("LINE の署名", () => {
  it("HMAC-SHA256 の base64 と一致すれば通す", async () => {
    const body = '{"events":[]}';
    // 自前の hmac 関数を通さず、Web Crypto で直接計算した値と照らす。
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode("line-secret"), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
    const sig = btoa(String.fromCharCode(...mac));
    expect(await verifyLineSignature("line-secret", body, sig)).toBe(true);
    expect(await verifyLineSignature("line-secret", body + " ", sig)).toBe(false);
    expect(await verifyLineSignature("line-secret", body, null)).toBe(false);
  });
  it("連携コードを入れたトークを開く URL", () => {
    expect(linkMessageUrl("@gymnee", "123456")).toBe("https://line.me/R/oaMessage/%40gymnee/?%E9%80%A3%E6%90%BA%20123456");
  });
});

describe("毎日の通知の判断", () => {
  it("今日記録した人には送らない", () => {
    expect(decideNotice("daily", summaryWith(0, true))).toBeNull();
  });
  it("途切れそうなときだけ: 3〜5 日目だけ", () => {
    expect(decideNotice("lapse", summaryWith(2))).toBeNull();
    expect(decideNotice("lapse", summaryWith(3))).toEqual({ kind: "lapse", lapsing: true });
    expect(decideNotice("lapse", summaryWith(5))).toEqual({ kind: "lapse", lapsing: true });
    expect(decideNotice("lapse", summaryWith(6))).toBeNull();
    expect(decideNotice("lapse", summaryWith(null))).toBeNull();
  });
  it("毎日: 途切れそうなら途切れそう用の文にする。メニュー提案は毎日", () => {
    expect(decideNotice("daily", summaryWith(1))).toEqual({ kind: "daily", lapsing: false });
    expect(decideNotice("daily", summaryWith(4))).toEqual({ kind: "lapse", lapsing: true });
    expect(decideNotice("daily_menu", summaryWith(4))).toEqual({ kind: "daily_menu", lapsing: true });
    expect(decideNotice("off", summaryWith(4))).toBeNull();
  });
  it("通数が減ったら途切れそうな人だけ。0 なら送らない。上限なしなら送る", () => {
    expect(reserveFor(200)).toBe(20);
    expect(allowPush("daily", false, 100, 200)).toBe(true);
    expect(allowPush("daily", false, 20, 200)).toBe(false);
    expect(allowPush("daily_menu", true, 20, 200)).toBe(true);
    expect(allowPush("lapse", true, 0, 200)).toBe(false);
    expect(allowPush("daily", false, null, null)).toBe(true);
  });
});

describe("LINE の文", () => {
  it("同じセットはまとめて書く", () => {
    const r = confirmLog(
      { name: "胸", date: NOW, completedAt: NOW, durationSeconds: null, note: null, exercises: [{ exercise: bench, sets: [1, 2, 3].map(() => ({ weightKg: 60, reps: 10, durationSeconds: null, distanceKm: null })) }] },
      "p1",
    );
    expect(r.text).toContain("ベンチプレス 60kg × 10（3セット）");
    expect(r.buttons?.map((b) => b.data)).toEqual(["log:p1", "cancel:p1"]);
  });
  it("メニューを「やった」で記録の入力にする", () => {
    const input = planToLogInput({ title: "胸", exercises: [{ name: "ベンチプレス", sets: 3, reps: 8, weightKg: 60 }, { name: "腕立て伏せ", sets: 2, reps: 15, weightKg: 0 }] });
    expect(input.exercises[0]!.sets).toHaveLength(3);
    expect(input.exercises[1]!.sets[0]).toEqual({ reps: 15 });
  });
  it("ふりかえりは記録から作る（AI を使わない）", () => {
    expect(weeklyReview(summaryWith(1)).text).toContain("今週は 0/3 回");
  });
  it("AI の出力: 壊れた値は既定に倒し、生の JSON を返答に出さない", () => {
    expect(parseCoachOutput({ intent: "weird", reply: "やあ" })?.intent).toBe("chat");
    expect(parseCoachOutput({ intent: "chat", reply: '{"reply": "x"}' })?.reply).toBe("");
    expect(parseCoachOutput("not an object")).toBeNull();
  });
});

// ---- webhook の流れ（偽の DB・偽の LINE・偽の Gemini） ----

function setup(options: { linked?: boolean; gemini?: unknown } = {}) {
  const replies: LineMessage[][] = [];
  const pushes: { to: string; messages: LineMessage[] }[] = [];
  const pending = new Map<string, { payload: unknown; consumed: boolean }>();
  const logged: unknown[] = [];
  const coachMessages: { body: string; isFromCoach: boolean; channel?: string; proposal?: unknown }[] = [];
  let link: LineLinkRow | null = options.linked
    ? { user_id: USER, line_user_id: LINE_USER, notify_mode: "daily", notify_hour: 7, last_notified_on: null, linked_at: "", updated_at: "" }
    : null;
  const codes = new Map([["123456", USER]]);
  const workouts: WorkoutRecord[] = [];
  const repo = {
    lineLinkByLineUser: async (id: string) => (link && link.line_user_id === id ? link : null),
    unlinkLineUser: async () => { link = null; },
    recordLinkAttempt: async () => 1,
    consumeLinkCode: async (code: string) => { const u = codes.get(code) ?? null; codes.delete(code); return u; },
    linkLine: async (userId: string, lineUserId: string) => {
      link = { user_id: userId, line_user_id: lineUserId, notify_mode: "daily", notify_hour: 7, last_notified_on: null, linked_at: "", updated_at: "" };
      return "linked" as const;
    },
    takeAiQuota: async () => true,
    exercises: async () => [bench, incline],
    recentCoachMessages: async () => [],
    addCoachMessage: async (_u: string, m: { body: string; isFromCoach: boolean; channel?: string; proposal?: unknown }) => { coachMessages.push(m); return { id: "cm1" }; },
    createPendingLog: async (_u: string, payload: unknown) => { const id = `p${pending.size + 1}`; pending.set(id, { payload, consumed: false }); return id; },
    pendingLog: async (_u: string, id: string) => { const p = pending.get(id); return p && !p.consumed ? p.payload : null; },
    updatePendingLog: async (_u: string, id: string, payload: unknown) => { pending.get(id)!.payload = payload; },
    consumePendingLog: async (_u: string, id: string) => { const p = pending.get(id); if (!p || p.consumed) return false; p.consumed = true; return true; },
    coachProposal: async () => ({ title: "胸", exercises: [{ name: "ベンチプレス", sets: 3, reps: 8, weightKg: 60 }] }),
    profile: async () => ({ id: USER, displayName: "たろう" }),
    weeklyGoal: async () => 3,
    completedWorkouts: async () => workouts,
    personalRecords: async () => [],
    setsForExercises: async () => [],
    logWorkout: async (_u: string, payload: Record<string, unknown>) => { logged.push(payload); return { workout_id: payload.id as string, created: true }; },
    claimLineNotifications: async () => (link ? [link] : []),
  } as unknown as Repo;
  const line = {
    reply: async (_t: string, messages: LineMessage[]) => { replies.push(messages); return true; },
    push: async (to: string, messages: LineMessage[]) => { pushes.push({ to, messages }); return { ok: true, status: 200 }; },
    remainingQuota: async () => ({ limit: 200, used: 10, remaining: 190 }),
  } as unknown as LineClient;
  const geminiFetch: typeof fetch = async () =>
    Response.json({ candidates: [{ content: { parts: [{ text: JSON.stringify(options.gemini ?? { intent: "chat", reply: "いいね" }) }] }, finishReason: "STOP" }] });
  const deps = { env, repo, line, now: () => NOW, geminiFetch };
  const ev = (e: { type: string } & Record<string, unknown>) => ({ replyToken: "rt", source: { type: "user", userId: LINE_USER }, ...e });
  return { deps, replies, pushes, pending, logged, coachMessages, ev, getLink: () => link };
}

const lastText = (replies: LineMessage[][]) => String((replies.at(-1)?.[0] as { text?: string })?.text ?? "");
const lastButtons = (replies: LineMessage[][]) =>
  ((replies.at(-1)?.[0] as { quickReply?: { items: { action: { data?: string; label: string } }[] } })?.quickReply?.items ?? []).map((i) => i.action.data ?? i.action.label);

describe("LINE の webhook", () => {
  it("連携していない人には、連携の仕方だけを返す", async () => {
    const t = setup();
    await handleLineEvents(t.deps, [t.ev({ type: "message", message: { type: "text", text: "こんにちは" } })]);
    expect(lastText(t.replies)).toContain("LINE と連携");
  });

  it("連携コードで紐付ける", async () => {
    const t = setup();
    await handleLineEvents(t.deps, [t.ev({ type: "message", message: { type: "text", text: "連携 １２３４５６" } })]);
    expect(t.getLink()?.user_id).toBe(USER);
    expect(lastText(t.replies)).toContain("連携しました");
  });

  it("グループからのメッセージには答えない（個人の記録を見せない）", async () => {
    const t = setup({ linked: true });
    await handleLineEvents(t.deps, [{ replyToken: "rt", source: { type: "group", userId: LINE_USER }, type: "message", message: { type: "text", text: "今週どう？" } }]);
    expect(t.replies).toHaveLength(0);
  });

  it("記録を伝えると確認を出し、「記録する」で 1 回だけ記録する", async () => {
    const t = setup({ linked: true, gemini: { intent: "log", reply: "この内容で記録する？", log: { name: "胸", exercises: [{ name: "ベンチプレス", sets: [{ weightKg: 60, reps: 10 }, { weightKg: 60, reps: 10 }] }] } } });
    await handleLineEvents(t.deps, [t.ev({ type: "message", message: { type: "text", text: "ベンチ60kg10回2セットやった" } })]);
    expect(lastText(t.replies)).toContain("この内容で記録する？");
    expect(lastButtons(t.replies)).toEqual(["log:p1", "cancel:p1"]);
    await handleLineEvents(t.deps, [t.ev({ type: "postback", postback: { data: "log:p1" } }), t.ev({ type: "postback", postback: { data: "log:p1" } })]);
    expect(t.logged).toHaveLength(1);
    expect(String((t.replies.at(-2)?.[0] as { text: string }).text)).toContain("記録した");
    expect(lastText(t.replies)).toContain("時間切れ"); // 2 回目は記録しない
  });

  it("種目が決まらなければ候補から選ばせ、選んだら確認に進む", async () => {
    const t = setup({ linked: true, gemini: { intent: "log", reply: "", log: { exercises: [{ name: "ベンチ", sets: [{ weightKg: 40, reps: 10 }] }] } } });
    await handleLineEvents(t.deps, [t.ev({ type: "message", message: { type: "text", text: "ベンチ40kg10回" } })]);
    expect(lastText(t.replies)).toContain("「ベンチ」はどれ？");
    const pick = lastButtons(t.replies).find((d) => d.startsWith(`pick:p1:0:${incline.id}`))!;
    await handleLineEvents(t.deps, [t.ev({ type: "postback", postback: { data: pick } })]);
    expect(lastText(t.replies)).toContain("インクラインベンチプレス 40kg × 10");
  });

  it("相談はコーチの会話としてアプリと共有する（channel=line）", async () => {
    const t = setup({ linked: true, gemini: { intent: "chat", reply: "肩を避けて脚にしよう" } });
    await handleLineEvents(t.deps, [t.ev({ type: "message", message: { type: "text", text: "肩が痛い" } })]);
    expect(lastText(t.replies)).toBe("肩を避けて脚にしよう");
    expect(t.coachMessages.map((m) => [m.isFromCoach, m.channel])).toEqual([[false, "line"], [true, "line"]]);
  });

  it("今日のメニューはアプリのコーチ画面にも提案を届け、「やった」で記録に進める", async () => {
    const t = setup({ linked: true, gemini: { intent: "menu", reply: "今日は胸", plan: { title: "胸", exercises: [{ name: "ベンチプレス", sets: 3, reps: 8, weightKg: 60 }] } } });
    await handleLineEvents(t.deps, [t.ev({ type: "postback", postback: { data: "rm:menu" } })]);
    expect(lastText(t.replies)).toContain("今日のメニュー: 胸");
    expect(t.coachMessages.at(-1)).toMatchObject({ isFromCoach: true, channel: "line", proposal: { title: "胸" } });
    await handleLineEvents(t.deps, [t.ev({ type: "postback", postback: { data: "doneplan:cm1" } })]);
    expect(lastText(t.replies)).toContain("この内容で記録する？");
  });

  it("ブロックされたら紐付けを消す", async () => {
    const t = setup({ linked: true });
    await handleLineEvents(t.deps, [t.ev({ type: "unfollow" })]);
    expect(t.getLink()).toBeNull();
  });
});

describe("LINE の毎日の通知", () => {
  it("その時刻の人に 1 通送る（今日まだ記録していなければ）", async () => {
    const t = setup({ linked: true });
    const r = await runLineDaily(env, t.deps.repo, NOW, t.deps.line, t.deps.geminiFetch);
    expect(r).toMatchObject({ claimed: 1, sent: 1 });
    expect(t.pushes[0]!.to).toBe(LINE_USER);
    expect(String((t.pushes[0]!.messages[0] as { text: string }).text)).toContain("今週は 0/3 回");
  });
});
