// Slack と Discord の「追加」ボタン（OAuth）。チャンネルを選ぶだけで、投稿用の Webhook URL を受け取る。
// URL を貼り付けさせない（AI に詳しくない人でも迷わず、URL の取り違えも起きない）。
//
// 流れ: アプリ → /app/{slack,discord}/start で認可 URL を受け取り、ASWebAuthenticationSession で開く
//   → 利用者がチャンネルを選ぶ → /{slack,discord}/callback（state を確かめ、code を Webhook URL に引き換える）
//   → 送り先を保存し、つながったことを 1 通送る → gymnee://connect/done?... でアプリに戻る

import type { Env } from "../env.js";
import { signState, verifyState } from "../domain/crypto.js";
import { checkDestinationUrl } from "../domain/destinationUrl.js";

export type ChatProvider = "slack" | "discord";

const STATE_TTL_SECONDS = 600;

export function providerConfigured(env: Env, provider: ChatProvider): boolean {
  return provider === "slack" ? Boolean(env.SLACK_CLIENT_ID && env.SLACK_CLIENT_SECRET) : Boolean(env.DISCORD_CLIENT_ID && env.DISCORD_CLIENT_SECRET);
}

export function callbackUrl(env: Env, provider: ChatProvider): string {
  return `${env.PUBLIC_ORIGIN}/${provider}/callback`;
}

export async function authorizeUrl(env: Env, provider: ChatProvider, userId: string): Promise<string> {
  const state = await signState(env.STATE_SECRET, { u: userId, k: provider, exp: Math.floor(Date.now() / 1000) + STATE_TTL_SECONDS });
  if (provider === "slack") {
    const u = new URL("https://slack.com/oauth/v2/authorize");
    u.searchParams.set("client_id", env.SLACK_CLIENT_ID ?? "");
    u.searchParams.set("scope", "incoming-webhook");
    u.searchParams.set("redirect_uri", callbackUrl(env, provider));
    u.searchParams.set("state", state);
    return u.toString();
  }
  const u = new URL("https://discord.com/oauth2/authorize");
  u.searchParams.set("client_id", env.DISCORD_CLIENT_ID ?? "");
  u.searchParams.set("response_type", "code");
  u.searchParams.set("scope", "webhook.incoming");
  u.searchParams.set("redirect_uri", callbackUrl(env, provider));
  u.searchParams.set("state", state);
  u.searchParams.set("prompt", "consent");
  return u.toString();
}

export interface ExchangedWebhook {
  userId: string;
  url: string;
  label: string;
}

/** コールバックの code を Webhook URL に引き換える。state が正しくなければ null（誰のものか分からない）。 */
export async function exchange(
  env: Env,
  provider: ChatProvider,
  params: URLSearchParams,
  doFetch: typeof fetch = (i, init) => fetch(i, init),
): Promise<{ ok: true; webhook: ExchangedWebhook } | { ok: false; reason: string; userId?: string }> {
  const state = await verifyState(env.STATE_SECRET, params.get("state") ?? "", provider);
  if (!state) return { ok: false, reason: "時間切れか、別の画面から来たリクエストです。アプリからやり直してください。" };
  if (params.get("error")) return { ok: false, reason: "キャンセルされました。", userId: state.u };
  const code = params.get("code");
  if (!code) return { ok: false, reason: "つなげませんでした。", userId: state.u };

  if (provider === "slack") {
    const res = await doFetch("https://slack.com/api/oauth.v2.access", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code,
        client_id: env.SLACK_CLIENT_ID ?? "",
        client_secret: env.SLACK_CLIENT_SECRET ?? "",
        redirect_uri: callbackUrl(env, provider),
      }),
    });
    const json = (await res.json().catch(() => ({}))) as {
      ok?: boolean;
      error?: string;
      team?: { name?: string };
      incoming_webhook?: { url?: string; channel?: string };
    };
    const url = json.incoming_webhook?.url;
    if (!json.ok || !url) return { ok: false, reason: "Slack とつなげませんでした。", userId: state.u };
    const checked = checkDestinationUrl(url);
    if (!checked.ok || checked.kind !== "slack") return { ok: false, reason: "Slack から想定外の URL が返りました。", userId: state.u };
    const channel = json.incoming_webhook?.channel ?? "Slack";
    const team = json.team?.name;
    return { ok: true, webhook: { userId: state.u, url: checked.url, label: team ? `${channel}（${team}）` : channel } };
  }

  const res = await doFetch("https://discord.com/api/oauth2/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${btoa(`${env.DISCORD_CLIENT_ID ?? ""}:${env.DISCORD_CLIENT_SECRET ?? ""}`)}`,
    },
    body: new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: callbackUrl(env, provider) }),
  });
  const json = (await res.json().catch(() => ({}))) as { webhook?: { url?: string; name?: string }; guild?: { name?: string } };
  const url = json.webhook?.url;
  if (!res.ok || !url) return { ok: false, reason: "Discord とつなげませんでした。", userId: state.u };
  const checked = checkDestinationUrl(url);
  if (!checked.ok || checked.kind !== "discord") return { ok: false, reason: "Discord から想定外の URL が返りました。", userId: state.u };
  const guild = json.guild?.name;
  return { ok: true, webhook: { userId: state.u, url: checked.url, label: guild ? `Discord（${guild}）` : "Discord" } };
}

/** アプリへ戻す URL（ASWebAuthenticationSession が gymnee:// を受け取って閉じる）。 */
export function backToApp(provider: ChatProvider, ok: boolean, message?: string): string {
  const u = new URL("gymnee://connect/done");
  u.searchParams.set("kind", provider);
  u.searchParams.set("status", ok ? "ok" : "error");
  if (message) u.searchParams.set("message", message);
  return u.toString();
}
