// 配信の結果から、次にどうするかを決める（純粋）。
// - 2xx: 成功
// - 送り先が消された（Slack の 404/410/403、Discord の 404/401）: すぐに送り先を止める
// - 429: Retry-After に従って再試行
// - それ以外の失敗: 間隔をあけて再試行し、6 回で諦める。続けて 5 回諦めた送り先は止める

import type { DestinationKind } from "./destinationUrl.js";

export const MAX_ATTEMPTS = 6;
export const DISABLE_AFTER_CONSECUTIVE_FAILURES = 5;
/** 再試行の間隔（分）。attempts 回目の失敗のあとに待つ時間。 */
const BACKOFF_MINUTES = [1, 5, 30, 120, 360];

export type DeliveryOutcome =
  | { kind: "succeeded" }
  | { kind: "retry"; at: Date; reason: string }
  | { kind: "failed"; reason: string }
  | { kind: "gone"; reason: string };

export function decideOutcome(input: {
  destinationKind: DestinationKind;
  /** 何回目の試行だったか（1 始まり）。 */
  attempt: number;
  status: number | null;
  retryAfterSeconds?: number | null;
  now: Date;
}): DeliveryOutcome {
  const { status, attempt, now } = input;
  if (status !== null && status >= 200 && status < 300) return { kind: "succeeded" };

  const goneStatuses = input.destinationKind === "slack" ? [403, 404, 410] : input.destinationKind === "discord" ? [401, 404] : [410];
  if (status !== null && goneStatuses.includes(status)) {
    return { kind: "gone", reason: "送り先が見つからない（チャンネルか Webhook が消された）" };
  }

  const reason = status === null ? "通信できなかった" : `送り先が ${status} を返した`;
  if (attempt >= MAX_ATTEMPTS) return { kind: "failed", reason };

  if (status === 429 && input.retryAfterSeconds && input.retryAfterSeconds > 0) {
    const wait = Math.min(input.retryAfterSeconds, 3600);
    return { kind: "retry", at: new Date(now.getTime() + wait * 1000), reason };
  }
  const minutes = BACKOFF_MINUTES[Math.min(attempt - 1, BACKOFF_MINUTES.length - 1)]!;
  return { kind: "retry", at: new Date(now.getTime() + minutes * 60_000), reason };
}
