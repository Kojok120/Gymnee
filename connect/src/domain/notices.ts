// 送り先に届ける知らせの中身と、Slack / Discord / 汎用 Webhook それぞれの形（純粋）。
// 名前や記録名は利用者が自由に書けるので、チャンネル全体への呼び出し（@everyone・<!channel>）に化けないよう必ず無害にする。

import { muscleLabel, setVolume, type ExerciseInfo, type SetRecord, type WorkoutRecord } from "./types.js";
import { jstMonthDay, addDays } from "./time.js";
import type { DestinationKind } from "./destinationUrl.js";

export const GYMNEE_ICON = "https://gymnee.app/assets/gymnee-icon.png";
/** 達成の色（Gymnee Lime）。 */
const LIME = 0xc6ff3d;

// ---- 中身 ----

export interface WorkoutNotice {
  type: "workout.completed";
  userName: string;
  inviteUrl: string;
  workout: {
    id: string;
    name: string;
    completedAt: string;
    durationMinutes: number | null;
    exerciseCount: number;
    setCount: number;
    volumeKg: number;
    exercises: { name: string; muscle: string; sets: number; best: string }[];
  };
  personalRecords: { exercise: string; best: string }[];
  week: { workouts: number; goal: number; streakWeeks: number };
}

export interface WeeklyNotice {
  type: "weekly.summary";
  userName: string;
  inviteUrl: string;
  /** 週の初日（JST の月曜 0 時）。 */
  weekStart: string;
  weekLabel: string;
  week: { workouts: number; goal: number; sets: number; volumeKg: number; muscles: string[]; streakWeeks: number };
  parties: { name: string; bossName: string; defeated: boolean; remainingHp: number; hp: number; myHits: number }[];
}

export interface HelloNotice {
  type: "connection.test";
  userName: string;
  inviteUrl: string;
}

export type Notice = WorkoutNotice | WeeklyNotice | HelloNotice;

/** セット 1 つを人が読む形にする（計測タイプで書き方が違う）。 */
export function describeSet(exercise: ExerciseInfo | null, set: SetRecord): string {
  const kind = exercise?.measurementType ?? "weight";
  switch (kind) {
    case "weight":
      return `${trimNumber(set.weightKg)}kg × ${set.reps}`;
    case "bodyweight":
      if (set.weightKg > 0) return `+${trimNumber(set.weightKg)}kg × ${set.reps}`;
      if (set.weightKg < 0) return `補助 ${trimNumber(-set.weightKg)}kg × ${set.reps}`;
      return `${set.reps} 回`;
    case "time":
      return duration(set.durationSeconds ?? 0);
    case "cardio": {
      const parts = [];
      if (set.distanceKm) parts.push(`${trimNumber(set.distanceKm)}km`);
      if (set.durationSeconds) parts.push(duration(set.durationSeconds));
      return parts.join("・") || "有酸素";
    }
  }
}

function trimNumber(v: number): string {
  return Number.isInteger(v) ? String(v) : String(Math.round(v * 10) / 10);
}

function duration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  if (m === 0) return `${s}秒`;
  return s === 0 ? `${m}分` : `${m}分${s}秒`;
}

/** いちばん良かったセット（重量 × 回数の大きいもの。重量が無ければ回数・時間・距離の大きいもの）。 */
function bestSet(sets: SetRecord[]): SetRecord | null {
  const score = (s: SetRecord) => setVolume(s) * 1000 + s.reps + (s.durationSeconds ?? 0) + (s.distanceKm ?? 0) * 100;
  return sets.reduce<SetRecord | null>((acc, s) => (acc === null || score(s) > score(acc) ? s : acc), null);
}

export function workoutNotice(input: {
  workout: WorkoutRecord;
  userName: string;
  inviteUrl: string;
  week: { workouts: number; goal: number; streakWeeks: number };
}): WorkoutNotice {
  const w = input.workout;
  const exercises = w.exercises.filter((e) => e.sets.length > 0);
  const prs: WorkoutNotice["personalRecords"] = [];
  for (const e of exercises) {
    const prSets = e.sets.filter((s) => s.isPR);
    const top = bestSet(prSets);
    if (top) prs.push({ exercise: e.exercise?.name ?? "種目", best: describeSet(e.exercise, top) });
  }
  return {
    type: "workout.completed",
    userName: input.userName,
    inviteUrl: input.inviteUrl,
    workout: {
      id: w.id,
      name: w.name,
      completedAt: w.completedAt,
      durationMinutes: w.durationSeconds ? Math.round(w.durationSeconds / 60) : null,
      exerciseCount: exercises.length,
      setCount: exercises.reduce((n, e) => n + e.sets.length, 0),
      volumeKg: Math.round(exercises.reduce((v, e) => v + e.sets.reduce((x, s) => x + setVolume(s), 0), 0)),
      exercises: exercises.map((e) => {
        const top = bestSet(e.sets);
        return {
          name: e.exercise?.name ?? "種目",
          muscle: muscleLabel(e.exercise?.muscleGroup),
          sets: e.sets.length,
          best: top ? describeSet(e.exercise, top) : "",
        };
      }),
    },
    personalRecords: prs,
    week: input.week,
  };
}

export function weekLabel(weekStart: Date): string {
  return `${jstMonthDay(weekStart)}〜${jstMonthDay(addDays(weekStart, 6))}`;
}

// ---- 無害化 ----

/** Slack の mrkdwn: & < > を実体参照にする（<!channel> や <@U…> を作らせない）。 */
export function slackEscape(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/** Discord: @ の直後に見えない文字を挟み、@everyone / @here / <@id> の呼び出しにさせない（allowed_mentions でも止める）。 */
export function discordEscape(text: string): string {
  return text.replace(/@/g, "@​").replace(/[`*_~|>]/g, (c) => `\\${c}`);
}

function clip(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`;
}

function formatKg(v: number): string {
  return `${v.toLocaleString("ja-JP")} kg`;
}

// ---- 送り先ごとの形 ----

function headline(n: Notice): string {
  switch (n.type) {
    case "workout.completed":
      return `${n.userName} が「${n.workout.name}」を記録しました`;
    case "weekly.summary":
      return `${n.userName} の先週のふりかえり（${n.weekLabel}）`;
    case "connection.test":
      return "Gymnee とつながりました";
  }
}

function slackBody(n: Notice): Record<string, unknown> {
  const e = slackEscape;
  const blocks: Record<string, unknown>[] = [];
  if (n.type === "workout.completed") {
    blocks.push({ type: "section", text: { type: "mrkdwn", text: `*${e(n.userName)}* が *${e(n.workout.name)}* を記録しました` } });
    const fields = [
      { type: "mrkdwn", text: `*種目*\n${n.workout.exerciseCount}` },
      { type: "mrkdwn", text: `*セット*\n${n.workout.setCount}` },
    ];
    if (n.workout.volumeKg > 0) fields.push({ type: "mrkdwn", text: `*総量*\n${formatKg(n.workout.volumeKg)}` });
    if (n.workout.durationMinutes) fields.push({ type: "mrkdwn", text: `*時間*\n${n.workout.durationMinutes} 分` });
    blocks.push({ type: "section", fields });
    const lines = n.workout.exercises.slice(0, 8).map((x) => `• ${e(x.name)}  ${e(x.best)}（${x.sets} セット）`);
    if (lines.length) blocks.push({ type: "section", text: { type: "mrkdwn", text: lines.join("\n") } });
    if (n.personalRecords.length) {
      blocks.push({ type: "section", text: { type: "mrkdwn", text: `*自己ベスト更新*\n${n.personalRecords.map((p) => `• ${e(p.exercise)}  ${e(p.best)}`).join("\n")}` } });
    }
    blocks.push({
      type: "context",
      elements: [{ type: "mrkdwn", text: `今週 ${n.week.workouts}/${n.week.goal} 回${n.week.streakWeeks > 0 ? ` · 目標達成 ${n.week.streakWeeks} 週連続` : ""} · <${n.inviteUrl}|Gymnee で一緒に記録する>` }],
    });
  } else if (n.type === "weekly.summary") {
    blocks.push({ type: "header", text: { type: "plain_text", text: clip(headline(n), 150) } });
    blocks.push({
      type: "section",
      fields: [
        { type: "mrkdwn", text: `*回数*\n${n.week.workouts} / 目標 ${n.week.goal}` },
        { type: "mrkdwn", text: `*セット*\n${n.week.sets}` },
        ...(n.week.volumeKg > 0 ? [{ type: "mrkdwn", text: `*総量*\n${formatKg(n.week.volumeKg)}` }] : []),
        { type: "mrkdwn", text: `*連続*\n${n.week.streakWeeks} 週` },
      ],
    });
    if (n.week.muscles.length) blocks.push({ type: "context", elements: [{ type: "mrkdwn", text: `鍛えた部位: ${e(n.week.muscles.join("・"))}` }] });
    for (const p of n.parties) {
      const status = p.defeated ? `${e(p.bossName)} を撃破` : `${e(p.bossName)} の残り HP ${p.remainingHp} / ${p.hp}`;
      blocks.push({ type: "section", text: { type: "mrkdwn", text: `*パーティ「${e(p.name)}」*  ${status}（自分の攻撃 ${p.myHits} 回）` } });
    }
    blocks.push({ type: "context", elements: [{ type: "mrkdwn", text: `<${n.inviteUrl}|Gymnee で一緒に記録する>` }] });
  } else {
    blocks.push({ type: "section", text: { type: "mrkdwn", text: `*Gymnee とつながりました*\n${e(n.userName)} が記録を終えると、ここにお知らせします。` } });
  }
  // text は通知のプレビューと、ブロックを出せないクライアント用。
  return { text: headline(n), blocks, unfurl_links: false, unfurl_media: false };
}

function discordBody(n: Notice): Record<string, unknown> {
  const d = discordEscape;
  let embed: Record<string, unknown>;
  if (n.type === "workout.completed") {
    const fields = [
      { name: "種目", value: String(n.workout.exerciseCount), inline: true },
      { name: "セット", value: String(n.workout.setCount), inline: true },
      ...(n.workout.volumeKg > 0 ? [{ name: "総量", value: formatKg(n.workout.volumeKg), inline: true }] : []),
      ...(n.workout.durationMinutes ? [{ name: "時間", value: `${n.workout.durationMinutes} 分`, inline: true }] : []),
    ];
    const lines = n.workout.exercises.slice(0, 8).map((x) => `${d(x.name)}  ${d(x.best)}（${x.sets} セット）`);
    if (lines.length) fields.push({ name: "内容", value: clip(lines.join("\n"), 1024), inline: false });
    if (n.personalRecords.length) {
      fields.push({ name: "自己ベスト更新", value: clip(n.personalRecords.map((p) => `${d(p.exercise)}  ${d(p.best)}`).join("\n"), 1024), inline: false });
    }
    embed = {
      title: clip(n.workout.name, 256),
      description: clip(`${d(n.userName)} が記録しました`, 4096),
      color: LIME,
      fields,
      footer: { text: `今週 ${n.week.workouts}/${n.week.goal} 回${n.week.streakWeeks > 0 ? ` · 目標達成 ${n.week.streakWeeks} 週連続` : ""}` },
      timestamp: n.workout.completedAt,
      url: n.inviteUrl,
    };
  } else if (n.type === "weekly.summary") {
    const fields = [
      { name: "回数", value: `${n.week.workouts} / 目標 ${n.week.goal}`, inline: true },
      { name: "セット", value: String(n.week.sets), inline: true },
      ...(n.week.volumeKg > 0 ? [{ name: "総量", value: formatKg(n.week.volumeKg), inline: true }] : []),
      { name: "連続", value: `${n.week.streakWeeks} 週`, inline: true },
      ...n.parties.map((p) => ({
        name: clip(`パーティ「${d(p.name)}」`, 256),
        value: `${p.defeated ? `${d(p.bossName)} を撃破` : `${d(p.bossName)} の残り HP ${p.remainingHp} / ${p.hp}`}（自分の攻撃 ${p.myHits} 回）`,
        inline: false,
      })),
    ];
    embed = {
      title: clip(headline(n), 256),
      description: n.week.muscles.length ? `鍛えた部位: ${d(n.week.muscles.join("・"))}` : undefined,
      color: LIME,
      fields,
      url: n.inviteUrl,
    };
  } else {
    embed = { title: "Gymnee とつながりました", description: `${d(n.userName)} が記録を終えると、ここにお知らせします。`, color: LIME, url: n.inviteUrl };
  }
  return { username: "Gymnee", avatar_url: GYMNEE_ICON, embeds: [embed], allowed_mentions: { parse: [] } };
}

/** 汎用 Webhook は、構造のまま渡す（受け取る側が自由に使えるように）。 */
function webhookBody(n: Notice, timestamp: string): Record<string, unknown> {
  const { type, ...data } = n;
  return { type, timestamp, data };
}

export function renderNotice(kind: DestinationKind, notice: Notice, now: Date = new Date()): string {
  switch (kind) {
    case "slack":
      return JSON.stringify(slackBody(notice));
    case "discord":
      return JSON.stringify(discordBody(notice));
    case "webhook":
      return JSON.stringify(webhookBody(notice, now.toISOString()));
  }
}
