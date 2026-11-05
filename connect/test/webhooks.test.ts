import { describe, expect, it } from "vitest";
import { checkDestinationUrl } from "../src/domain/destinationUrl.js";
import { sign, generateWebhookSecret } from "../src/domain/standardWebhooks.js";
import { decideOutcome, MAX_ATTEMPTS } from "../src/domain/deliveryPolicy.js";
import { describeSet, discordEscape, renderNotice, slackEscape, workoutNotice, type WeeklyNotice } from "../src/domain/notices.js";
import { isWeeklyWindow, runDeliveries } from "../src/jobs/deliver.js";
import { authorizeUrl, exchange } from "../src/integrations/chatOAuth.js";
import { encryptString, bytesToBase64 } from "../src/domain/crypto.js";
import type { Env } from "../src/env.js";
import type { DeliveryRow, DestinationSecretRow, Repo } from "../src/db/repo.js";
import type { ExerciseInfo, WorkoutRecord } from "../src/domain/types.js";

const bench: ExerciseInfo = { id: "11111111-1111-4111-8111-111111111111", name: "ベンチプレス", muscleGroup: "chest", equipment: "barbell", measurementType: "weight", loadMode: "none", isCustom: false };
const pullup: ExerciseInfo = { id: "22222222-2222-4222-8222-222222222222", name: "アシスト懸垂", muscleGroup: "back", equipment: "machine", measurementType: "bodyweight", loadMode: "assisted", isCustom: false };
const USER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const KEY = bytesToBase64(new Uint8Array(32).map((_, i) => i + 1));

const env = {
  PUBLIC_ORIGIN: "https://api.gymnee.app",
  SITE_ORIGIN: "https://gymnee.app",
  ENCRYPTION_KEY: KEY,
  STATE_SECRET: "s".repeat(40),
  SLACK_CLIENT_ID: "slack-id",
  SLACK_CLIENT_SECRET: "slack-secret",
  DISCORD_CLIENT_ID: "discord-id",
  DISCORD_CLIENT_SECRET: "discord-secret",
} as unknown as Env;

function workout(): WorkoutRecord {
  return {
    id: "w1", name: "胸と背中", date: "2026-11-05T09:00:00Z", completedAt: "2026-11-05T10:00:00Z", durationSeconds: 2700, note: null,
    exercises: [
      { exercise: bench, sets: [
        { index: 0, weightKg: 60, reps: 10, durationSeconds: null, distanceKm: null, isPR: false },
        { index: 1, weightKg: 62.5, reps: 8, durationSeconds: null, distanceKm: null, isPR: true },
      ] },
      { exercise: pullup, sets: [{ index: 0, weightKg: -10, reps: 8, durationSeconds: null, distanceKm: null, isPR: false }] },
    ],
  };
}

describe("送り先の URL", () => {
  it("Slack / Discord / 汎用を見分ける", () => {
    expect(checkDestinationUrl("https://hooks.slack.com/services/T000/B000/abcDEF123")).toMatchObject({ ok: true, kind: "slack" });
    expect(checkDestinationUrl("https://discord.com/api/webhooks/123456/abc-DEF_1")).toMatchObject({ ok: true, kind: "discord" });
    expect(checkDestinationUrl("https://discordapp.com/api/v10/webhooks/123456/abc")).toMatchObject({ ok: true, kind: "discord" });
    expect(checkDestinationUrl("https://example.com/hooks/gymnee?x=1")).toMatchObject({ ok: true, kind: "webhook", label: "example.com" });
  });
  it("内部の宛先・http・ポート・資格情報つきは断る", () => {
    for (const bad of [
      "http://example.com/hook",
      "https://127.0.0.1/hook",
      "https://[::1]/hook",
      "https://localhost/hook",
      "https://printer.local/hook",
      "https://intranet/hook",
      "https://example.com:8443/hook",
      "https://user:pass@example.com/hook",
      "https://hooks.slack.com/workflows/T0/A0/1/abc",
      "https://discord.com/channels/1/2",
      "not a url",
    ]) {
      expect(checkDestinationUrl(bad).ok, bad).toBe(false);
    }
  });
});

describe("Standard Webhooks の署名", () => {
  it("仕様の例と一致する", async () => {
    // https://github.com/standard-webhooks/standard-webhooks の例（Python の hmac でも同じ値になることを確かめた）
    expect(await sign("whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw", "msg_p5jXN8AQM9LWM0D4loKWxJek", 1614265330, '{"test": 2432232314}')).toBe(
      "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=",
    );
  });
  it("鍵は whsec_ で始まり毎回違う", () => {
    const a = generateWebhookSecret();
    expect(a.startsWith("whsec_")).toBe(true);
    expect(a).not.toBe(generateWebhookSecret());
  });
});

describe("配信の結果の扱い", () => {
  const now = new Date("2026-11-05T12:00:00Z");
  it("2xx は成功", () => {
    expect(decideOutcome({ destinationKind: "slack", attempt: 1, status: 200, now }).kind).toBe("succeeded");
  });
  it("消された送り先はすぐ止める", () => {
    expect(decideOutcome({ destinationKind: "slack", attempt: 1, status: 404, now }).kind).toBe("gone");
    expect(decideOutcome({ destinationKind: "discord", attempt: 1, status: 404, now }).kind).toBe("gone");
    expect(decideOutcome({ destinationKind: "webhook", attempt: 1, status: 404, now }).kind).toBe("retry");
  });
  it("429 は Retry-After に従い、ほかは間隔をあけて、6 回で諦める", () => {
    const r429 = decideOutcome({ destinationKind: "discord", attempt: 1, status: 429, retryAfterSeconds: 30, now });
    expect(r429.kind === "retry" && r429.at.getTime() - now.getTime()).toBe(30_000);
    const r500 = decideOutcome({ destinationKind: "webhook", attempt: 2, status: 500, now });
    expect(r500.kind === "retry" && r500.at.getTime() - now.getTime()).toBe(5 * 60_000);
    expect(decideOutcome({ destinationKind: "webhook", attempt: MAX_ATTEMPTS, status: null, now }).kind).toBe("failed");
  });
});

describe("知らせの中身", () => {
  it("セットの書き方は計測タイプごと", () => {
    expect(describeSet(bench, { index: 0, weightKg: 62.5, reps: 8, durationSeconds: null, distanceKm: null, isPR: false })).toBe("62.5kg × 8");
    expect(describeSet(pullup, { index: 0, weightKg: -10, reps: 8, durationSeconds: null, distanceKm: null, isPR: false })).toBe("補助 10kg × 8");
  });

  const notice = () =>
    workoutNotice({ workout: workout(), userName: "<!channel> @everyone たろう", inviteUrl: "https://gymnee.app/invite?u=x", week: { workouts: 2, goal: 3, streakWeeks: 1 } });

  it("記録の要約・自己ベスト・今週の回数", () => {
    const n = notice();
    expect(n.workout).toMatchObject({ exerciseCount: 2, setCount: 3, volumeKg: 1100, durationMinutes: 45 });
    expect(n.personalRecords).toEqual([{ exercise: "ベンチプレス", best: "62.5kg × 8" }]);
  });

  it("Slack: 名前の <!channel> を無害にする", () => {
    const body = JSON.parse(renderNotice("slack", notice()));
    const text = JSON.stringify(body.blocks);
    expect(text).not.toContain("<!channel>");
    expect(text).toContain("&lt;!channel&gt;");
    expect(slackEscape("a<b>&")).toBe("a&lt;b&gt;&amp;");
  });

  it("Discord: @everyone で呼び出させない（allowed_mentions も空）", () => {
    const body = JSON.parse(renderNotice("discord", notice()));
    expect(body.allowed_mentions).toEqual({ parse: [] });
    expect(JSON.stringify(body.embeds)).not.toContain("@everyone");
    expect(discordEscape("@here")).toBe("@​here");
  });

  it("汎用 Webhook は構造のまま", () => {
    const body = JSON.parse(renderNotice("webhook", notice(), new Date("2026-11-05T10:02:00Z")));
    expect(body.type).toBe("workout.completed");
    expect(body.timestamp).toBe("2026-11-05T10:02:00.000Z");
    expect(body.data.workout.setCount).toBe(3);
  });

  it("週のふりかえり: パーティは合計と本人の分だけ", () => {
    const weekly: WeeklyNotice = {
      type: "weekly.summary", userName: "たろう", inviteUrl: "https://gymnee.app/invite?u=x",
      weekStart: "2026-10-26T15:00:00.000Z", weekLabel: "10月27日〜11月2日",
      week: { workouts: 3, goal: 3, sets: 30, volumeKg: 9000, muscles: ["胸", "背中"], streakWeeks: 2 },
      parties: [{ name: "朝トレ部", bossName: "サボリスライム", defeated: false, remainingHp: 2, hp: 9, myHits: 3 }],
    };
    const text = renderNotice("slack", weekly);
    expect(text).toContain("サボリスライム の残り HP 2 / 9");
    expect(text).toContain("自分の攻撃 3 回");
  });
});

describe("週のふりかえりの時間", () => {
  it("月曜 8 時台（JST）だけ", () => {
    expect(isWeeklyWindow(new Date("2026-11-08T23:30:00Z"))).toBe(true); // 11/9（月）8:30 JST
    expect(isWeeklyWindow(new Date("2026-11-09T00:00:00Z"))).toBe(false); // 9:00 JST
    expect(isWeeklyWindow(new Date("2026-11-09T23:30:00Z"))).toBe(false); // 火曜
  });
});

describe("Slack / Discord の追加ボタン", () => {
  it("state に利用者と用途を載せ、取り違えを断る", async () => {
    const url = new URL(await authorizeUrl(env, "slack", USER));
    expect(url.searchParams.get("scope")).toBe("incoming-webhook");
    expect(url.searchParams.get("redirect_uri")).toBe("https://api.gymnee.app/slack/callback");
    const state = url.searchParams.get("state")!;
    // Discord の戻り先に Slack の state を持ってきても通さない
    const wrong = await exchange(env, "discord", new URLSearchParams({ state, code: "c" }), async () => new Response("{}"));
    expect(wrong.ok).toBe(false);
    const fakeSlack: typeof fetch = async () =>
      Response.json({ ok: true, team: { name: "朝トレ部" }, incoming_webhook: { url: "https://hooks.slack.com/services/T1/B1/abc", channel: "#gym" } });
    const ok = await exchange(env, "slack", new URLSearchParams({ state, code: "c" }), fakeSlack);
    expect(ok).toMatchObject({ ok: true, webhook: { userId: USER, label: "#gym（朝トレ部）" } });
  });
  it("想定外の URL が返ったら保存しない", async () => {
    const url = new URL(await authorizeUrl(env, "discord", USER));
    const evil: typeof fetch = async () => Response.json({ webhook: { url: "https://evil.example/steal" } });
    const r = await exchange(env, "discord", new URLSearchParams({ state: url.searchParams.get("state")!, code: "c" }), evil);
    expect(r.ok).toBe(false);
  });
});

describe("配信のジョブ", () => {
  it("取り出した配信を送り、成功・再試行・消された送り先を書き分ける", async () => {
    const finished: { id: string; status: string }[] = [];
    const destinationEvents: string[] = [];
    const dest = async (kind: "slack" | "discord" | "webhook", url: string): Promise<DestinationSecretRow> => ({
      id: `d-${kind}`, user_id: USER, kind, label: kind, events: ["workout.completed"], consecutive_failures: 0,
      disabled_at: null, disabled_reason: null, last_delivered_at: null, created_at: "",
      target_ciphertext: await encryptString(KEY, url), signing_secret_ciphertext: kind === "webhook" ? await encryptString(KEY, "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw") : null,
    });
    const dests = { "d-slack": await dest("slack", "https://hooks.slack.com/services/T/B/ok"), "d-discord": await dest("discord", "https://discord.com/api/webhooks/1/gone"), "d-webhook": await dest("webhook", "https://example.com/flaky") };
    const delivery = (id: string, destinationId: string): DeliveryRow => ({
      id, destination_id: destinationId, user_id: USER, event_type: "workout.completed", subject_key: "workout.completed:w1",
      subject_id: "w1", period_start: null, status: "pending", attempts: 1, next_attempt_at: "",
    });
    const repo = {
      fanoutEvents: async () => 3,
      enqueueWeekly: async () => 0,
      claimDeliveries: async () => [delivery("x1", "d-slack"), delivery("x2", "d-discord"), delivery("x3", "d-webhook")],
      destinationWithSecrets: async (userId: string, id: string) => (userId === USER ? dests[id as keyof typeof dests] : null),
      workout: async () => workout(),
      profile: async () => ({ id: USER, displayName: "たろう" }),
      weeklyGoal: async () => 3,
      completedWorkouts: async () => [workout()],
      finishDelivery: async (d: DeliveryRow, r: { status: string }) => { finished.push({ id: d.id, status: r.status }); },
      destinationSucceeded: async (_u: string, id: string) => { destinationEvents.push(`ok:${id}`); },
      destinationFailed: async (_u: string, id: string, _n: number, _max: number, reason?: string) => { destinationEvents.push(`fail:${id}:${reason ? "disabled" : "count"}`); },
      purge: async () => undefined,
    } as unknown as Repo;
    const seen: { url: string; headers: Headers; body: string }[] = [];
    const fakeFetch: typeof fetch = async (input, init) => {
      const url = String(input);
      seen.push({ url, headers: new Headers(init?.headers), body: String(init?.body) });
      if (url.endsWith("/ok")) return new Response("ok", { status: 200 });
      if (url.endsWith("/gone")) return new Response("Unknown Webhook", { status: 404 });
      return new Response("busy", { status: 503 });
    };
    const r = await runDeliveries(env, repo, new Date("2026-11-05T03:00:00Z"), fakeFetch);
    expect(r).toMatchObject({ fannedOut: 3, sent: 3, errors: 0 });
    expect(finished.sort((a, b) => a.id.localeCompare(b.id))).toEqual([
      { id: "x1", status: "succeeded" },
      { id: "x2", status: "failed" },
      { id: "x3", status: "pending" },
    ]);
    expect(destinationEvents.sort()).toEqual(["fail:d-discord:disabled", "ok:d-slack"]);
    // 汎用 Webhook には Standard Webhooks の署名が付き、id は配信の id（再試行でも同じ）
    const hook = seen.find((s) => s.url.endsWith("/flaky"))!;
    expect(hook.headers.get("webhook-id")).toBe("x3");
    expect(hook.headers.get("webhook-signature")).toMatch(/^v1,/);
    const slack = seen.find((s) => s.url.endsWith("/ok"))!;
    expect(slack.headers.get("webhook-signature")).toBeNull();
    expect(JSON.parse(slack.body).text).toContain("胸と背中");
  });
});
