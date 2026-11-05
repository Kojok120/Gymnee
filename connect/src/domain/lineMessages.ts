// LINE に送る文とボタン（純粋）。AI に詳しくない人でも、ボタンを押すだけで進められるようにする。
// ボタン（クイックリプライ）の data は postback として webhook に戻る。形は `<動作>:<id>`。

import type { LogWorkoutInput } from "./workoutInput.js";
import type { ResolvedWorkout } from "./workoutInput.js";
import type { Summary } from "./summary.js";
import { describeSet } from "./notices.js";

export const APP_STORE_URL = "https://apps.apple.com/jp/app/id6782380051";

export interface Button {
  label: string;
  data?: string;
  text?: string;
}

export interface Reply {
  text: string;
  buttons?: Button[];
}

// ---- リッチメニュー・定型の postback ----
export const POSTBACK = {
  menu: "rm:menu",
  lightMenu: "rm:menu-light",
  howToLog: "rm:log",
  review: "rm:review",
  consult: "rm:consult",
  rest: "rest",
} as const;

export const MENU_BUTTONS: Button[] = [
  { label: "今日のメニュー", data: POSTBACK.menu },
  { label: "記録する", data: POSTBACK.howToLog },
  { label: "今週のふりかえり", data: POSTBACK.review },
];

export function welcomeUnlinked(): Reply {
  return {
    text:
      "Gymnee の公式アカウントです。\nアプリの「その他 > 連携 > LINE と連携」を押すと、記録とつながり、ここでコーチに相談したり記録したりできます。\n" +
      `アプリがまだなら: ${APP_STORE_URL}`,
  };
}

export function linkedNow(): Reply {
  return {
    text:
      "連携しました。ここで話しかけると、コーチがあなたの記録を見て答えます。\n" +
      "例:「ベンチ 60kg 10回 3セットやった」「今日のメニューは？」「肩が痛い」\n" +
      "通知の出し方は、アプリの「その他 > 連携」で選べます。",
    buttons: MENU_BUTTONS,
  };
}

export function linkFailed(reason: "expired" | "too_many" | "already"): Reply {
  switch (reason) {
    case "expired":
      return { text: "連携コードが違うか、時間切れです。アプリの「LINE と連携」を、もう一度押してください。" };
    case "too_many":
      return { text: "連携コードを何度も間違えたので、しばらく受け付けません。1 時間ほどしてから、アプリでもう一度試してください。" };
    case "already":
      return { text: "この LINE は、すでに別の Gymnee のアカウントと連携しています。アプリの「連携」で解除してから、もう一度試してください。" };
  }
}

export function howToLog(): Reply {
  return {
    text: "やったことを、そのまま送ってください。\n例:「ベンチプレス 60kg 10回 3セット」「懸垂 8回 3セット」「ランニング 5km 30分」\n内容を確かめてから記録します。",
  };
}

export function consult(): Reply {
  return {
    text: "どうしましたか？ 気になっていることを、そのまま送ってください。",
    buttons: [
      { label: "時間がない", text: "今日は時間がない。短いメニューにして" },
      { label: "やる気が出ない", text: "やる気が出ない" },
      { label: "肩が痛い", text: "肩が痛い" },
      { label: "伸び悩んでいる", text: "最近伸び悩んでいる" },
    ],
  };
}

export function rest(): Reply {
  return { text: "了解。休むのも大事。また声をかけるね。" };
}

export function notLinkedYet(): Reply {
  return welcomeUnlinked();
}

export function quotaExceeded(): Reply {
  return { text: "今日はたくさん話したので、コーチはここまで。また明日話そう。記録は「記録する」から続けられます。", buttons: [{ label: "記録する", data: POSTBACK.howToLog }] };
}

export function aiUnavailable(): Reply {
  return { text: "うまく言葉にできなかった。少ししてから、もう一度送ってくれる？" };
}

// ---- ふりかえり（AI を使わず、記録から作る） ----

export function weeklyReview(s: Summary): Reply {
  const lines = [`今週は ${s.thisWeek.workouts}/${s.weeklyGoal} 回・${s.thisWeek.sets} セット${s.thisWeek.volumeKg > 0 ? `・総量 ${s.thisWeek.volumeKg.toLocaleString("ja-JP")}kg` : ""}。`];
  if (s.thisWeek.muscles.length) lines.push(`鍛えた部位: ${s.thisWeek.muscles.slice(0, 4).map((m) => m.label).join("・")}`);
  if (s.streakWeeks > 0) lines.push(`目標達成は ${s.streakWeeks} 週連続。`);
  lines.push(`先週は ${s.lastWeek.workouts} 回でした。`);
  const left = s.weeklyGoal - s.thisWeek.workouts;
  lines.push(left > 0 ? `目標まであと ${left} 回。` : "今週の目標は達成。この調子。");
  return { text: lines.join("\n"), buttons: [{ label: "今日のメニュー", data: POSTBACK.menu }] };
}

// ---- 記録の確認 ----

export function describeResolved(w: ResolvedWorkout): string {
  const lines = w.exercises.map((e) => {
    const sets = e.sets.map((s) => describeSet(e.exercise, { index: 0, ...s, isPR: false }));
    // 同じ内容のセットが続くときは「× 3」にまとめる。
    const grouped: string[] = [];
    let i = 0;
    while (i < sets.length) {
      let j = i;
      while (j + 1 < sets.length && sets[j + 1] === sets[i]) j++;
      grouped.push(j > i ? `${sets[i]}（${j - i + 1}セット）` : sets[i]!);
      i = j + 1;
    }
    return `・${e.exercise.name} ${grouped.join("、")}`;
  });
  return `${w.name}\n${lines.join("\n")}`;
}

export function confirmLog(w: ResolvedWorkout, pendingId: string): Reply {
  return {
    text: `この内容で記録する？\n${describeResolved(w)}`,
    buttons: [
      { label: "記録する", data: `log:${pendingId}` },
      { label: "やめる", data: `cancel:${pendingId}` },
    ],
  };
}

export function pickExercise(original: string, candidates: { id: string; name: string }[], pendingId: string, exerciseIndex: number): Reply {
  return {
    text: `「${original}」はどれ？`,
    buttons: [
      ...candidates.slice(0, 4).map((c) => ({ label: c.name, data: `pick:${pendingId}:${exerciseIndex}:${c.id}` })),
      { label: "やめる", data: `cancel:${pendingId}` },
    ],
  };
}

export function logged(result: { name: string; exercises: { name: string; sets: number }[]; personalRecords: { exercise: string; label: string; value: number }[] }): Reply {
  const sets = result.exercises.reduce((n, e) => n + e.sets, 0);
  const lines = [`記録した。${result.name}（${result.exercises.length}種目・${sets}セット）。おつかれさま。`];
  if (result.personalRecords.length) {
    lines.push(`自己ベスト更新: ${result.personalRecords.map((p) => `${p.exercise} ${p.label} ${p.value}`).join("、")}`);
  }
  lines.push("アプリを開くと反映されます。");
  return { text: lines.join("\n") };
}

export function logCancelled(): Reply {
  return { text: "やめました。もう一度送れば、記録し直せます。" };
}

export function logExpired(): Reply {
  return { text: "この確認は時間切れです。もう一度、やったことを送ってください。" };
}

export function logProblem(messages: string[]): Reply {
  return { text: `記録できませんでした。${messages.slice(0, 3).join("。")}。書き直して送ってください。` };
}

// ---- メニュー ----

export interface MenuPlan {
  title: string;
  exercises: { name: string; sets: number; reps: number; weightKg: number }[];
}

export function menuText(plan: MenuPlan, lead: string): string {
  const lines = plan.exercises.map((e) => `・${e.name} ${e.weightKg > 0 ? `${e.weightKg}kg × ` : ""}${e.reps}回 × ${e.sets}セット`);
  return `${lead ? `${lead}\n` : ""}今日のメニュー: ${plan.title}\n${lines.join("\n")}\nアプリのコーチ画面からも取り込めます。`;
}

export function menuReply(plan: MenuPlan, lead: string, messageId: string): Reply {
  return {
    text: menuText(plan, lead),
    buttons: [
      { label: "やった！記録する", data: `doneplan:${messageId}` },
      { label: "別のメニュー", data: POSTBACK.menu },
      { label: "今日は休む", data: POSTBACK.rest },
    ],
  };
}

/** メニューを「やった」とき、そのまま記録の入力にする。 */
export function planToLogInput(plan: MenuPlan): LogWorkoutInput {
  return {
    name: plan.title.slice(0, 60),
    exercises: plan.exercises.map((e) => ({
      name: e.name,
      sets: Array.from({ length: Math.max(1, Math.min(10, Math.round(e.sets))) }, () =>
        e.weightKg > 0 ? { weightKg: e.weightKg, reps: Math.round(e.reps) } : { reps: Math.round(e.reps) },
      ),
    })),
  };
}
