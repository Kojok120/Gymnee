// 送り先への配信（cron で毎分）。
//   1. 待ち時間を過ぎた知らせを送り先ごとに展開する（connect_fanout_events）
//   2. 月曜の朝 8 時台なら、先週のふりかえりを積む（何度呼んでも 1 回分）
//   3. 送る順番の来た配信を取り出して送り、結果を書く（失敗は間隔をあけて再試行）
//   4. 毎朝 4 時台に古いものを掃除する
// 本文は送るときにその時点のデータで作る（完了の直後はまだセットが届いていないことがあるため）。

import type { Env } from "../env.js";
import type { DeliveryRow, Repo } from "../db/repo.js";
import { decryptString } from "../domain/crypto.js";
import { decideOutcome, DISABLE_AFTER_CONSECUTIVE_FAILURES } from "../domain/deliveryPolicy.js";
import { renderNotice, weekLabel, workoutNotice, type Notice } from "../domain/notices.js";
import { signedHeaders } from "../domain/standardWebhooks.js";
import { buildSummary, workoutsInWeek, weekTotals } from "../domain/summary.js";
import { addDays, jstHour, jstWeekStart } from "../domain/time.js";
import { bossName } from "../domain/party.js";

const SEND_TIMEOUT_MS = 10_000;
const USER_AGENT = "Gymnee-Webhooks/1.0 (+https://gymnee.app/connect/)";

export function inviteUrl(env: Env, userId: string): string {
  return `${env.SITE_ORIGIN}/invite?u=${userId}`;
}

async function displayName(repo: Repo, userId: string): Promise<string> {
  return (await repo.profile(userId))?.displayName ?? "Gymnee のユーザー";
}

/** 配信の行から、届ける中身を作る。中身が作れない（記録が消された・その週に記録が無い）ときは null。 */
export async function buildNotice(env: Env, repo: Repo, d: DeliveryRow, now: Date): Promise<Notice | null> {
  const userId = d.user_id;
  if (d.event_type === "workout.completed" && d.subject_id) {
    const [workout, name, goal, recent] = await Promise.all([
      repo.workout(userId, d.subject_id),
      displayName(repo, userId),
      repo.weeklyGoal(userId),
      repo.completedWorkouts(userId, { from: addDays(now, -120), limit: 500 }),
    ]);
    if (!workout) return null;
    const summary = buildSummary(recent, goal, new Date(workout.completedAt));
    return workoutNotice({
      workout,
      userName: name,
      inviteUrl: inviteUrl(env, userId),
      week: { workouts: summary.thisWeek.workouts, goal, streakWeeks: summary.streakWeeks },
    });
  }
  if (d.event_type === "weekly.summary" && d.period_start) {
    const weekStart = new Date(d.period_start);
    const weekEnd = addDays(weekStart, 7);
    const [name, goal, recent, parties] = await Promise.all([
      displayName(repo, userId),
      repo.weeklyGoal(userId),
      repo.completedWorkouts(userId, { from: addDays(weekStart, -120), to: weekEnd, limit: 500 }),
      repo.partyOverview(userId, addDays(weekStart, 3)),
    ]);
    const inWeek = workoutsInWeek(recent, weekStart);
    // 記録の無かった週は送らない（チームのチャンネルで「0 回」をさらさない）。
    if (inWeek.length === 0) return null;
    const totals = weekTotals(inWeek);
    const asOfWeekEnd = new Date(weekEnd.getTime() - 1);
    return {
      type: "weekly.summary",
      userName: name,
      inviteUrl: inviteUrl(env, userId),
      weekStart: weekStart.toISOString(),
      weekLabel: weekLabel(weekStart),
      week: {
        workouts: totals.workouts,
        goal,
        sets: totals.sets,
        volumeKg: totals.volumeKg,
        muscles: totals.muscles.slice(0, 5).map((m) => m.label),
        streakWeeks: buildSummary(recent, goal, asOfWeekEnd).streakWeeks,
      },
      parties: parties.map((p) => ({
        name: p.name ?? "パーティ",
        bossName: bossName(p.boss_id),
        defeated: p.defeated,
        remainingHp: Math.max(0, p.hp - p.damage),
        hp: p.hp,
        myHits: p.my_hits,
      })),
    };
  }
  return null;
}

/** 1 件を送って結果を返す（HTTP の状態だけ。判断は decideOutcome）。 */
export async function send(
  env: Env,
  kind: "slack" | "discord" | "webhook",
  target: string,
  signingSecret: string | null,
  body: string,
  deliveryId: string,
  now: Date,
  doFetch: typeof fetch,
): Promise<{ status: number | null; retryAfter: number | null; error: string | null }> {
  const headers: Record<string, string> = { "Content-Type": "application/json", "User-Agent": USER_AGENT };
  if (kind === "webhook" && signingSecret) Object.assign(headers, await signedHeaders(signingSecret, deliveryId, Math.floor(now.getTime() / 1000), body));
  try {
    // 転送（3xx）には付いていかない（送り先の確かめを迂回させない）。
    const res = await doFetch(target, { method: "POST", headers, body, redirect: "manual", signal: AbortSignal.timeout(SEND_TIMEOUT_MS) });
    const retryAfter = Number(res.headers.get("Retry-After"));
    await res.body?.cancel();
    return { status: res.status, retryAfter: Number.isFinite(retryAfter) ? retryAfter : null, error: null };
  } catch (error) {
    return { status: null, retryAfter: null, error: error instanceof Error ? error.name : "fetch failed" };
  }
}

async function deliverOne(env: Env, repo: Repo, d: DeliveryRow, now: Date, doFetch: typeof fetch): Promise<void> {
  const dest = await repo.destinationWithSecrets(d.user_id, d.destination_id);
  if (!dest || dest.disabled_at) {
    await repo.finishDelivery(d, { status: "failed", httpStatus: null, error: "送り先が止まっている" });
    return;
  }
  const notice = await buildNotice(env, repo, d, now);
  if (!notice) {
    await repo.finishDelivery(d, { status: "succeeded", httpStatus: null, error: "送る中身が無いので送らなかった" });
    return;
  }
  const target = await decryptString(env.ENCRYPTION_KEY, dest.target_ciphertext);
  const secret = dest.signing_secret_ciphertext ? await decryptString(env.ENCRYPTION_KEY, dest.signing_secret_ciphertext) : null;
  const result = await send(env, dest.kind, target, secret, renderNotice(dest.kind, notice, now), d.id, now, doFetch);
  const outcome = decideOutcome({ destinationKind: dest.kind, attempt: d.attempts, status: result.status, retryAfterSeconds: result.retryAfter, now });
  switch (outcome.kind) {
    case "succeeded":
      await repo.finishDelivery(d, { status: "succeeded", httpStatus: result.status, error: null });
      await repo.destinationSucceeded(d.user_id, dest.id);
      return;
    case "retry":
      await repo.finishDelivery(d, { status: "pending", nextAttemptAt: outcome.at, httpStatus: result.status, error: result.error ?? outcome.reason });
      return;
    case "failed":
      await repo.finishDelivery(d, { status: "failed", httpStatus: result.status, error: result.error ?? outcome.reason });
      await repo.destinationFailed(d.user_id, dest.id, dest.consecutive_failures, DISABLE_AFTER_CONSECUTIVE_FAILURES);
      return;
    case "gone":
      await repo.finishDelivery(d, { status: "failed", httpStatus: result.status, error: outcome.reason });
      await repo.destinationFailed(d.user_id, dest.id, dest.consecutive_failures, DISABLE_AFTER_CONSECUTIVE_FAILURES, outcome.reason);
      return;
  }
}

/** 月曜の 8 時台（JST）か。この間は毎分呼ぶが、積むのは 1 回分だけ。 */
export function isWeeklyWindow(now: Date): boolean {
  const weekStart = jstWeekStart(now);
  const sameDay = now.getTime() - weekStart.getTime() < 86_400_000;
  return sameDay && jstHour(now) === 8;
}

export async function runDeliveries(env: Env, repo: Repo, now: Date = new Date(), doFetch: typeof fetch = (i, init) => fetch(i, init)) {
  const fannedOut = await repo.fanoutEvents(50);
  let weekly = 0;
  if (isWeeklyWindow(now)) weekly = await repo.enqueueWeekly(addDays(jstWeekStart(now), -7));
  const batch = await repo.claimDeliveries(25);
  const results = await Promise.allSettled(batch.map((d) => deliverOne(env, repo, d, now, doFetch)));
  const errors = results.filter((r) => r.status === "rejected").length;
  if (errors > 0) console.error("deliveries: some deliveries threw", errors);
  if (jstHour(now) === 4 && now.getUTCMinutes() < 2) await repo.purge();
  return { fannedOut, weekly, sent: batch.length, errors };
}

/** 送り先を足した直後のつながりの確かめ（すぐに 1 通送る。再試行はしない）。 */
export async function sendHello(
  env: Env,
  kind: "slack" | "discord" | "webhook",
  target: string,
  signingSecret: string | null,
  userName: string,
  userId: string,
  doFetch: typeof fetch = (i, init) => fetch(i, init),
): Promise<{ ok: boolean; status: number | null }> {
  const now = new Date();
  const body = renderNotice(kind, { type: "connection.test", userName, inviteUrl: inviteUrl(env, userId) }, now);
  const result = await send(env, kind, target, signingSecret, body, crypto.randomUUID(), now, doFetch);
  return { ok: result.status !== null && result.status >= 200 && result.status < 300, status: result.status };
}
