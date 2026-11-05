// LINE の毎日の通知（cron で毎分。その時刻に送る人を、今日まだの人だけ取り出して送る）。
// 1 人 1 日 1 通。今日もう記録した人には送らない。メニュー提案はアプリのコーチ画面にも届ける。
// 通知は通数に数えるので、残りが減ったら途切れそうな人だけに絞る（lineNotify.allowPush）。

import type { Env } from "../env.js";
import type { LineLinkRow, Repo } from "../db/repo.js";
import { GymneeService } from "../service.js";
import { LineClient, lineConfigured, text } from "../integrations/line.js";
import { allowPush, dailyNotice, decideNotice, lapseNotice, reserveFor } from "../domain/lineNotify.js";
import { jstDay, jstHour } from "../domain/time.js";
import { uuidV5 } from "../domain/ids.js";
import { coachTurn } from "../line/webhook.js";
import { aiUnavailable, quotaExceeded } from "../domain/lineMessages.js";

const PER_RUN = 20;

export interface LineDailyResult {
  claimed: number;
  sent: number;
  skipped: number;
  held: number;
}

export async function runLineDaily(env: Env, repo: Repo, now: Date = new Date(), line = new LineClient(env), geminiFetch?: typeof fetch): Promise<LineDailyResult> {
  const result: LineDailyResult = { claimed: 0, sent: 0, skipped: 0, held: 0 };
  if (!lineConfigured(env)) return result;
  const links = await repo.claimLineNotifications(jstHour(now), jstDay(now), PER_RUN);
  result.claimed = links.length;
  if (links.length === 0) return result;

  let quota: { limit: number | null; remaining: number | null };
  try {
    quota = await line.remainingQuota();
  } catch {
    quota = { limit: null, remaining: null };
  }
  let remaining = quota.remaining;

  for (const link of links) {
    try {
      const outcome = await notifyOne(env, repo, line, link, now, remaining, quota.limit, geminiFetch);
      if (outcome === "sent") {
        result.sent += 1;
        if (remaining !== null) remaining -= 1;
      } else if (outcome === "held") {
        result.held += 1;
      } else {
        result.skipped += 1;
      }
    } catch (error) {
      result.skipped += 1;
      console.error("line daily failed", error instanceof Error ? error.message : String(error));
    }
  }
  if (result.held > 0 || (remaining !== null && remaining <= reserveFor(quota.limit))) {
    await alertOps(env, `LINE の通数が残り ${remaining ?? "?"} 通（上限 ${quota.limit ?? "?"}）。途切れそうな人以外への通知を ${result.held} 件止めました。プランの見直しを検討してください。`);
  }
  return result;
}

async function notifyOne(
  env: Env,
  repo: Repo,
  line: LineClient,
  link: LineLinkRow,
  now: Date,
  remaining: number | null,
  limit: number | null,
  geminiFetch?: typeof fetch,
): Promise<"sent" | "skipped" | "held"> {
  const service = new GymneeService(repo, () => now);
  const summary = await service.summary(link.user_id);
  const decided = decideNotice(link.notify_mode, summary);
  if (!decided) return "skipped";
  if (!allowPush(decided.kind, decided.lapsing, remaining, limit)) return "held";

  let reply;
  if (decided.kind === "daily_menu") {
    // メニューを組んでアプリのコーチ画面にも届ける（AI の 1 日の上限の内で）。空いていれば軽めにする。
    reply = await coachTurn({ env, repo, line, now: () => now, geminiFetch }, link, decided.lapsing ? "しばらく空いたので、軽めのメニューを組んで" : "今日のメニューを組んで", decided.lapsing ? "light-menu" : "menu");
    // AI が使えない・上限に達したときは、ふつうの通知にする（「うまく言葉にできなかった」を通知で送らない）。
    if (reply.text === aiUnavailable().text || reply.text === quotaExceeded().text) {
      reply = decided.lapsing ? lapseNotice(summary) : dailyNotice(summary);
    }
  } else {
    reply = decided.kind === "lapse" ? lapseNotice(summary) : dailyNotice(summary);
  }
  // 同じ人に同じ日に 2 通送らないよう、LINE 側にも同じ鍵を渡す。
  const retryKey = await uuidV5(`line-daily:${link.user_id}:${jstDay(now)}`);
  const pushed = await line.push(link.line_user_id, [text(reply.text, reply.buttons)], retryKey);
  return pushed.ok ? "sent" : "skipped";
}

let lastAlertDay = "";

/** 運営への知らせ（Discord の Webhook。無ければログだけ）。1 日 1 回まで。 */
async function alertOps(env: Env, message: string): Promise<void> {
  console.error("ops alert", message);
  const day = jstDay(new Date());
  if (!env.OPS_ALERT_WEBHOOK_URL || lastAlertDay === day) return;
  lastAlertDay = day;
  await fetch(env.OPS_ALERT_WEBHOOK_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content: `Gymnee 外部連携: ${message}`, allowed_mentions: { parse: [] } }),
  }).catch(() => undefined);
}
