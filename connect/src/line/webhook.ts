// LINE の Webhook（友だち追加・ブロック・メッセージ・ボタン）。
// 返事はすべて Reply API で返す（通数に数えない）。AI を呼ぶのはテキストのメッセージと「今日のメニュー」だけ。
//
// 入口の約束:
//   - X-Line-Signature を確かめてから中身を読む
//   - LINE の利用者 id から持ち主（Gymnee の利用者 id）を引き、以降はその id だけで読み書きする
//   - 連携していない人には、アプリでの連携の仕方だけを返す（記録には一切触れない）

import type { Env } from "../env.js";
import type { LineLinkRow, Repo } from "../db/repo.js";
import { GymneeService } from "../service.js";
import { LineClient, text, type LineMessage } from "../integrations/line.js";
import { generateJson } from "../integrations/gemini.js";
import { buildTurns, parseCoachOutput, type CoachOutput } from "../domain/lineCoach.js";
import * as M from "../domain/lineMessages.js";
import { LogWorkoutInput, resolveWorkout } from "../domain/workoutInput.js";
import { jstDay } from "../domain/time.js";

/** LINE からの AI の呼び出しの 1 日の上限（Gemini の費用の歯止め。アプリの CoachQuota とは別に数える）。 */
export const LINE_AI_DAILY_LIMIT = 30;
const LINK_ATTEMPTS_PER_HOUR = 10;

interface LineEvent {
  type: string;
  replyToken?: string;
  source?: { type?: string; userId?: string };
  message?: { type?: string; text?: string };
  postback?: { data?: string };
}

export interface LineDeps {
  env: Env;
  repo: Repo;
  line: LineClient;
  now?: () => Date;
  geminiFetch?: typeof fetch;
}

function toMessages(r: M.Reply): LineMessage[] {
  return [text(r.text, r.buttons)];
}

export async function handleLineEvents(deps: LineDeps, events: LineEvent[]): Promise<void> {
  // 1 回の webhook に複数のイベントが来ることがある。利用者ごとに順番を守るため、順に処理する。
  for (const event of events) {
    try {
      await handleEvent(deps, event);
    } catch (error) {
      console.error("line event failed", event.type, error instanceof Error ? error.message : String(error));
    }
  }
}

async function handleEvent(deps: LineDeps, event: LineEvent): Promise<void> {
  const lineUserId = event.source?.userId;
  // グループやトークルームでは使わない（個人の記録を他人に見せない）。
  if (event.source?.type !== "user" || !lineUserId) return;
  const reply = async (r: M.Reply | LineMessage[]) => {
    if (event.replyToken) await deps.line.reply(event.replyToken, Array.isArray(r) ? r : toMessages(r));
  };

  if (event.type === "unfollow") {
    await deps.repo.unlinkLineUser(lineUserId);
    return;
  }

  const link = await deps.repo.lineLinkByLineUser(lineUserId);

  if (event.type === "follow") {
    await reply(link ? M.linkedNow() : M.welcomeUnlinked());
    return;
  }

  if (event.type === "message" && event.message?.type === "text") {
    const body = (event.message.text ?? "").trim();
    const codeMatch = /^連携\s*([0-9]{6})$/.exec(body.normalize("NFKC"));
    if (codeMatch) {
      await reply(await linkWithCode(deps, lineUserId, codeMatch[1]!));
      return;
    }
    if (!link) {
      await reply(M.notLinkedYet());
      return;
    }
    await reply(await coachTurn(deps, link, body, "free"));
    return;
  }

  if (event.type === "postback" && event.postback?.data) {
    if (!link) {
      await reply(M.notLinkedYet());
      return;
    }
    await reply(await handlePostback(deps, link, event.postback.data));
    return;
  }

  // スタンプ・画像など。使い方だけ返す。
  if (event.type === "message" && link) await reply({ text: "文字で送ってください。例:「今日のメニューは？」「ベンチ 60kg 10回 3セット」", buttons: M.MENU_BUTTONS });
}

async function linkWithCode(deps: LineDeps, lineUserId: string, code: string): Promise<M.Reply> {
  const attempts = await deps.repo.recordLinkAttempt(lineUserId);
  if (attempts > LINK_ATTEMPTS_PER_HOUR) return M.linkFailed("too_many");
  const userId = await deps.repo.consumeLinkCode(code);
  if (!userId) return M.linkFailed("expired");
  const result = await deps.repo.linkLine(userId, lineUserId);
  return result === "already" ? M.linkFailed("already") : M.linkedNow();
}

async function handlePostback(deps: LineDeps, link: LineLinkRow, data: string): Promise<M.Reply> {
  const userId = link.user_id;
  const service = new GymneeService(deps.repo, deps.now);
  const [action, ...rest] = data.split(":");
  switch (data) {
    case M.POSTBACK.menu:
      return coachTurn(deps, link, "今日のメニューを組んで", "menu");
    case M.POSTBACK.lightMenu:
      return coachTurn(deps, link, "しばらく空いたので、軽めのメニューを組んで", "light-menu");
    case M.POSTBACK.howToLog:
      return M.howToLog();
    case M.POSTBACK.review:
      return M.weeklyReview(await service.summary(userId));
    case M.POSTBACK.consult:
      return M.consult();
    case M.POSTBACK.rest:
      return M.rest();
  }
  switch (action) {
    case "log": {
      const id = rest[0] ?? "";
      const payload = await deps.repo.pendingLog(userId, id);
      if (!payload) return M.logExpired();
      const input = LogWorkoutInput.safeParse(payload);
      if (!input.success) return M.logExpired();
      // 先に押された方だけが記録する（2 回押しても 1 件）。鍵も確認待ちの id にして、念のため冪等にする。
      if (!(await deps.repo.consumePendingLog(userId, id))) return M.logExpired();
      const result = await service.logWorkout(userId, input.data, `line:${id}`);
      if (!result.ok) return M.logProblem(result.problems.map((p) => p.message));
      return M.logged(result);
    }
    case "cancel": {
      await deps.repo.consumePendingLog(userId, rest[0] ?? "");
      return M.logCancelled();
    }
    case "pick": {
      // 決まらなかった種目を、候補から選んでもらった。
      const [id, indexText, exerciseId] = rest;
      const payload = await deps.repo.pendingLog(userId, id ?? "");
      const input = LogWorkoutInput.safeParse(payload);
      if (!input.success || !id || !exerciseId) return M.logExpired();
      const index = Number(indexText);
      const target = input.data.exercises[index];
      if (!target) return M.logExpired();
      input.data.exercises[index] = { exerciseId, sets: target.sets };
      await deps.repo.updatePendingLog(userId, id, input.data);
      return confirmOrPick(deps, userId, input.data, id);
    }
    case "doneplan": {
      const plan = await deps.repo.coachProposal(userId, rest[0] ?? "");
      if (!plan) return M.logExpired();
      const input = M.planToLogInput(plan);
      const id = await deps.repo.createPendingLog(userId, input);
      return confirmOrPick(deps, userId, input, id);
    }
  }
  return { text: "その操作は分かりませんでした。", buttons: M.MENU_BUTTONS };
}

/** 入力を確かめ、決まれば確認を、種目が決まらなければ候補を、値が足りなければ理由を返す。 */
async function confirmOrPick(deps: LineDeps, userId: string, input: LogWorkoutInput, pendingId: string): Promise<M.Reply> {
  const catalog = await deps.repo.exercises(userId);
  const resolved = resolveWorkout(input, catalog, (deps.now ?? (() => new Date()))());
  if (resolved.ok) return M.confirmLog(resolved.workout, pendingId);
  const pick = resolved.problems.find((p) => p.candidates && p.candidates.length > 0 && p.exerciseIndex >= 0);
  if (pick) {
    const original = input.exercises[pick.exerciseIndex]?.name ?? "種目";
    return M.pickExercise(original, pick.candidates!, pendingId, pick.exerciseIndex);
  }
  await deps.repo.consumePendingLog(userId, pendingId);
  return M.logProblem(resolved.problems.map((p) => p.message));
}

/** AI のコーチとの 1 往復。会話はアプリのコーチ画面と共有する（coach_messages に channel=line で書く）。 */
export async function coachTurn(deps: LineDeps, link: LineLinkRow, message: string, mode: "free" | "menu" | "light-menu"): Promise<M.Reply> {
  const userId = link.user_id;
  const now = (deps.now ?? (() => new Date()))();
  if (!(await deps.repo.takeAiQuota(userId, jstDay(now), LINE_AI_DAILY_LIMIT))) return M.quotaExceeded();

  const service = new GymneeService(deps.repo, deps.now);
  const [summary, catalog, history] = await Promise.all([
    service.summary(userId),
    deps.repo.exercises(userId),
    deps.repo.recentCoachMessages(userId, 12),
  ]);
  const raw = await generateJson(
    deps.env,
    buildTurns({ summary, exerciseNames: catalog.map((e) => e.name), history, message, mode }),
    {},
    deps.geminiFetch,
  );
  const out = raw ? parseCoachOutput(raw) : null;
  if (!out) return M.aiUnavailable();

  // 利用者の発言を残す（ボタンからの定型文は残さない）。
  if (mode === "free") await deps.repo.addCoachMessage(userId, { body: message, isFromCoach: false, channel: "line" });
  return actOnCoachOutput(deps, userId, out, service, mode);
}

async function actOnCoachOutput(deps: LineDeps, userId: string, out: CoachOutput, service: GymneeService, mode: string): Promise<M.Reply> {
  if (out.intent === "log" && out.log && mode === "free") {
    const input = LogWorkoutInput.safeParse({ name: out.log.name, exercises: out.log.exercises });
    if (!input.success) return M.logProblem(["内容を読み取れませんでした"]);
    const id = await deps.repo.createPendingLog(userId, input.data);
    return confirmOrPick(deps, userId, input.data, id);
  }
  if ((out.intent === "menu" || mode !== "free") && out.plan) {
    const plan = { title: out.plan.title, exercises: out.plan.exercises };
    const lead = out.reply || "今日はこれでいこう。";
    const { messageId } = await service.proposeMenu(userId, { title: plan.title, message: lead, exercises: plan.exercises }, "line");
    return M.menuReply(plan, lead, messageId);
  }
  const reply = out.reply || "うまく言葉にできなかった。もう一度送ってくれる？";
  await deps.repo.addCoachMessage(userId, { body: reply, isFromCoach: true, channel: "line" });
  return { text: reply, buttons: M.MENU_BUTTONS };
}
