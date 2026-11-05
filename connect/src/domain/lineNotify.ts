// LINE の毎日の通知（純粋）: 送るか・何を送るか・通数の残りで間引くか。
// 「途切れそう」の判定はアプリのローカル通知（ReengagementReminder）と同じ: 最後の記録から 3 日目から 3 日分。

import type { Summary } from "./summary.js";
import type { Reply } from "./lineMessages.js";
import { POSTBACK } from "./lineMessages.js";

export type NotifyMode = "off" | "lapse" | "daily" | "daily_menu";
export type NoticeKind = "lapse" | "daily" | "daily_menu";

export const LAPSE_FROM_DAY = 3;
export const LAPSE_DAYS = 3;

export function isLapsing(summary: Summary): boolean {
  const d = summary.daysSinceLastWorkout;
  return d !== null && d >= LAPSE_FROM_DAY && d < LAPSE_FROM_DAY + LAPSE_DAYS;
}

/** 送るなら何を送るか。今日もう記録していれば送らない。 */
export function decideNotice(mode: NotifyMode, summary: Summary): { kind: NoticeKind; lapsing: boolean } | null {
  if (mode === "off" || summary.recordedToday) return null;
  const lapsing = isLapsing(summary);
  if (mode === "lapse") return lapsing ? { kind: "lapse", lapsing } : null;
  if (mode === "daily") return { kind: lapsing ? "lapse" : "daily", lapsing };
  return { kind: "daily_menu", lapsing };
}

/**
 * 今月の通数の残りで、送ってよいかを決める。
 * - 上限の無いプラン（remaining が null）なら送る
 * - 残りが「取っておく分」以下になったら、途切れそうな人への通知だけを送る
 * - 0 なら送らない
 */
export function allowPush(kind: NoticeKind, lapsing: boolean, remaining: number | null, limit: number | null): boolean {
  if (remaining === null) return true;
  if (remaining <= 0) return false;
  if (remaining <= reserveFor(limit)) return kind === "lapse" || lapsing;
  return true;
}

/** 途切れそうな人のために取っておく通数（上限の 1 割、少なくとも 10 通）。 */
export function reserveFor(limit: number | null): number {
  return Math.max(10, Math.ceil((limit ?? 200) * 0.1));
}

export function dailyNotice(summary: Summary): Reply {
  const last = summary.recentSessions[0];
  const lines = [`おはよう。今週は ${summary.thisWeek.workouts}/${summary.weeklyGoal} 回。`];
  if (last) lines.push(`前回は${last.daysAgo === 0 ? "今日" : `${last.daysAgo}日前`}（${last.muscles.slice(0, 3).join("・") || last.name}）。`);
  else lines.push("最初の 1 回をやってみよう。");
  lines.push("今日はどうする？");
  return {
    text: lines.join(""),
    buttons: [
      { label: "今日のメニュー", data: POSTBACK.menu },
      { label: "記録する", data: POSTBACK.howToLog },
      { label: "今日は休む", data: POSTBACK.rest },
    ],
  };
}

export function lapseNotice(summary: Summary): Reply {
  const d = summary.daysSinceLastWorkout ?? LAPSE_FROM_DAY;
  return {
    text: `最後の記録から ${d} 日。責めてないよ。軽めのメニューから戻そう。5 分だけでも十分。`,
    buttons: [
      { label: "軽めのメニュー", data: POSTBACK.lightMenu },
      { label: "記録する", data: POSTBACK.howToLog },
      { label: "今日は休む", data: POSTBACK.rest },
    ],
  };
}
