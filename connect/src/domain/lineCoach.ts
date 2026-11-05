// LINE のコーチ（純粋）: AI に渡す文と、返ってきた JSON の読み方。
// 人格と禁止事項は Edge Function の coach-chat（アプリのコーチ）と同じにする。変えるときは両方を直す。
// LINE ではメッセージ 1 通で「記録する」「メニュー」「相談」のどれかを AI に見分けさせる。

import { z } from "zod";
import type { Summary } from "./summary.js";

export const PERSONA = `
あなたは筋トレアプリ Gymnee のコーチです。利用者とは LINE で話しています。利用者の記録だけを根拠に、短く具体的に話します。

人格:
- 実務的で穏やか。淡々としているが冷たくない
- 1〜3文で答える。前置きや相槌だけの返事はしない
- 敬語は使わず、親しい指導者の口調（「〜しよう」「〜してみて」）
- 絵文字と記号の装飾（**・#・>）は使わない。LINE なので改行は少なめに

必ず守ること:
- サボりや空白期間を責めない。休むことを肯定し、軽い内容から戻す提案をする
- 痛み・不調を訴えられたら、その部位を避けたメニューに組み替える。診断や医療的な断定はせず、強い痛みが続く場合は医療機関を勧める
- 利用者の記録について、渡された内容に無い事実を作らない。分からないことは「記録が足りない」と言う
- 数値（重量・レップ）は直近の記録から地続きの範囲で提案する。急に大きく上げない
- アプリ内の報酬や強さを約束しない。強くなるのは現実のトレーニングだけ
`.trim();

export const RESPONSE_SHAPE = `
出力は次の JSON だけを返してください（前後に説明文を付けない）。

{
  "intent": "log" | "menu" | "chat",
  "reply": "利用者への返答（1〜3文）",
  "log": { "name": "記録の名前（例: 胸の日。省略可）", "exercises": [ { "name": "種目名", "sets": [ { "weightKg": 60, "reps": 10 } ] } ] },
  "plan": { "title": "メニュー名", "exercises": [ { "name": "種目名", "sets": 3, "reps": 10, "weightKg": 60 } ] }
}

- 利用者が「やったこと」を数字つきで伝えたら intent は "log"。log にその内容を入れる（plan は入れない）
  - 「3セット」は sets を 3 つ並べる。重さが書いていない自重種目は weightKg を省く。時間の種目は durationSeconds、有酸素は durationSeconds か distanceKm
  - 種目名は、下の「使える種目」から最も近いものを、表記そのままで書く。当てはまるものが無ければ利用者の言葉のまま書く
  - reply には「この内容で記録する？」のような確認の一言だけを書く
- メニューを聞かれた・組み替えを頼まれたら intent は "menu"。plan を入れる（種目名は「使える種目」から選ぶ。自重は weightKg 0。最大 6 種目）
- それ以外（相談・質問・雑談）は intent は "chat"。log と plan は入れない
`.trim();

export const CoachOutput = z.object({
  intent: z.enum(["log", "menu", "chat"]).catch("chat"),
  reply: z.string().catch(""),
  log: z
    .object({
      name: z.string().max(60).optional(),
      exercises: z
        .array(
          z.object({
            name: z.string().min(1).max(60),
            sets: z
              .array(
                z.object({
                  weightKg: z.number().optional(),
                  reps: z.number().int().optional(),
                  durationSeconds: z.number().int().optional(),
                  distanceKm: z.number().optional(),
                }),
              )
              .min(1)
              .max(30),
          }),
        )
        .min(1)
        .max(20),
    })
    .optional()
    .catch(undefined),
  plan: z
    .object({
      title: z.string().catch("今日のメニュー"),
      exercises: z
        .array(z.object({ name: z.string().min(1).max(60), sets: z.number(), reps: z.number(), weightKg: z.number().catch(0) }))
        .min(1)
        .max(8),
    })
    .optional()
    .catch(undefined),
});

export type CoachOutput = z.infer<typeof CoachOutput>;

/** AI に渡す「いまの状況」。名前・メールなど個人を特定できるものは入れない。 */
export function contextText(summary: Summary, exerciseNames: string[], mode: "free" | "menu" | "light-menu"): string {
  const brief = {
    weeklyGoal: summary.weeklyGoal,
    thisWeek: { workouts: summary.thisWeek.workouts, sets: summary.thisWeek.sets, volumeKg: summary.thisWeek.volumeKg, muscles: summary.thisWeek.muscles },
    lastWeek: { workouts: summary.lastWeek.workouts },
    streakWeeks: summary.streakWeeks,
    recordedToday: summary.recordedToday,
    daysSinceLastWorkout: summary.daysSinceLastWorkout,
    recentSessions: summary.recentSessions.slice(0, 6).map((s) => ({ daysAgo: s.daysAgo, title: s.name, sets: s.sets, volumeKg: s.volumeKg, muscles: s.muscles })),
  };
  const lines = [
    `いまの利用者の状況（記録の話はこの情報だけを根拠にしてください）:\n${JSON.stringify(brief)}`,
    `使える種目: ${exerciseNames.join("、")}`,
  ];
  if (mode === "menu") lines.push("今回は今日のメニューを 1 つ組んでください（intent は menu）。直近で鍛えていない部位を優先し、重量は直近の記録から地続きにする。");
  if (mode === "light-menu") lines.push("今回は、しばらく空いた人が戻るための軽めのメニューを 1 つ組んでください（intent は menu。種目は 3 つまで、普段より軽く）。");
  return lines.join("\n");
}

export function buildTurns(input: {
  summary: Summary;
  exerciseNames: string[];
  history: { isFromCoach: boolean; body: string }[];
  message: string;
  mode?: "free" | "menu" | "light-menu";
}): { role: "user" | "model"; text: string }[] {
  return [
    { role: "user", text: `${PERSONA}\n\n${RESPONSE_SHAPE}` },
    { role: "user", text: contextText(input.summary, input.exerciseNames, input.mode ?? "free") },
    ...input.history.slice(-12).map((m) => ({ role: (m.isFromCoach ? "model" : "user") as "user" | "model", text: m.body.slice(0, 1000) })),
    { role: "user", text: input.message.slice(0, 1000) },
  ];
}

/** AI の出力を読む。壊れていれば null（呼び出し側で「もう一度」と返す）。 */
export function parseCoachOutput(raw: unknown): CoachOutput | null {
  const parsed = CoachOutput.safeParse(raw);
  if (!parsed.success) return null;
  const out = parsed.data;
  // 生の JSON を返答として見せない。
  if (/^\s*[{[]/.test(out.reply) || out.reply.includes('"intent"')) out.reply = "";
  return out;
}
