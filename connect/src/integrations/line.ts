// LINE Messaging API の薄いクライアント。
// - Webhook の署名: base64(HMAC-SHA256(チャネルシークレット, 本文)) を X-Line-Signature と照らす
// - アクセストークン: チャネル ID とシークレットから短命のトークン（v3・15 分）を取り、使い回す
// - 返信（Reply）は通数に数えない。通知（Push）は数える。数の確かめは quota / consumption

import type { Env } from "../env.js";
import { bytesToBase64, hmacSha256, timingSafeEqual } from "../domain/crypto.js";

const API = "https://api.line.me";

export function lineConfigured(env: Env): boolean {
  return Boolean(env.LINE_MESSAGING_CHANNEL_ID && env.LINE_MESSAGING_CHANNEL_SECRET);
}

export async function verifyLineSignature(channelSecret: string, body: string, signature: string | null): Promise<boolean> {
  if (!signature) return false;
  const expected = bytesToBase64(await hmacSha256(channelSecret, body));
  return timingSafeEqual(expected, signature);
}

export type LineMessage = Record<string, unknown>;

/** クイックリプライ（メッセージの下に並ぶボタン）。ラベルは 20 文字まで。 */
export function quickReply(items: { label: string; data?: string; text?: string }[]): Record<string, unknown> {
  return {
    items: items.slice(0, 13).map((i) => ({
      type: "action",
      action: i.data
        ? { type: "postback", label: i.label.slice(0, 20), data: i.data.slice(0, 300), displayText: i.label.slice(0, 300) }
        : { type: "message", label: i.label.slice(0, 20), text: (i.text ?? i.label).slice(0, 300) },
    })),
  };
}

export function text(message: string, buttons?: { label: string; data?: string; text?: string }[]): LineMessage {
  return { type: "text", text: message.slice(0, 5000), ...(buttons?.length ? { quickReply: quickReply(buttons) } : {}) };
}

let cachedToken: { value: string; expiresAt: number } | null = null;

export class LineClient {
  constructor(
    private readonly env: Env,
    private readonly doFetch: typeof fetch = (i, init) => fetch(i, init),
  ) {}

  private async token(): Promise<string> {
    if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;
    const res = await this.doFetch(`${API}/oauth2/v3/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: this.env.LINE_MESSAGING_CHANNEL_ID ?? "",
        client_secret: this.env.LINE_MESSAGING_CHANNEL_SECRET ?? "",
      }),
    });
    if (!res.ok) throw new Error(`LINE token ${res.status}`);
    const json = (await res.json()) as { access_token: string; expires_in: number };
    cachedToken = { value: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
    return json.access_token;
  }

  private async call(path: string, init: RequestInit & { retryKey?: string } = {}): Promise<Response> {
    const headers = new Headers(init.headers);
    headers.set("Authorization", `Bearer ${await this.token()}`);
    if (init.body) headers.set("Content-Type", "application/json");
    if (init.retryKey) headers.set("X-Line-Retry-Key", init.retryKey);
    return this.doFetch(`${API}${path}`, { ...init, headers });
  }

  /** 返信（通数に数えない）。返信用のトークンは 1 回きり・しばらくで切れる。 */
  async reply(replyToken: string, messages: LineMessage[]): Promise<boolean> {
    const res = await this.call("/v2/bot/message/reply", {
      method: "POST",
      body: JSON.stringify({ replyToken, messages: messages.slice(0, 5) }),
    });
    if (!res.ok) console.error("line reply failed", res.status, (await res.text()).slice(0, 200));
    return res.ok;
  }

  /** 通知（通数に数える）。retryKey が同じなら LINE 側で二重に送らない。 */
  async push(to: string, messages: LineMessage[], retryKey: string): Promise<{ ok: boolean; status: number }> {
    const res = await this.call("/v2/bot/message/push", {
      method: "POST",
      body: JSON.stringify({ to, messages: messages.slice(0, 5) }),
      retryKey,
    });
    // 409 は同じ retryKey で既に送ったもの（届いている）。
    if (!res.ok && res.status !== 409) console.error("line push failed", res.status, (await res.text()).slice(0, 200));
    return { ok: res.ok || res.status === 409, status: res.status };
  }

  /** 今月の残りの通数。上限が無いプランなら null。 */
  async remainingQuota(): Promise<{ limit: number | null; used: number; remaining: number | null }> {
    const [quota, usage] = await Promise.all([
      this.call("/v2/bot/message/quota").then((r) => r.json() as Promise<{ type: string; value?: number }>),
      this.call("/v2/bot/message/quota/consumption").then((r) => r.json() as Promise<{ totalUsage: number }>),
    ]);
    const limit = quota.type === "limited" && typeof quota.value === "number" ? quota.value : null;
    const used = usage.totalUsage ?? 0;
    return { limit, used, remaining: limit === null ? null : Math.max(0, limit - used) };
  }
}

/** 公式アカウントのトークを、連携コードを入れた状態で開く URL（LINE の URL スキーム）。 */
export function linkMessageUrl(basicId: string, code: string): string {
  return `https://line.me/R/oaMessage/${encodeURIComponent(basicId)}/?${encodeURIComponent(`連携 ${code}`)}`;
}

export function addFriendUrl(basicId: string): string {
  return `https://line.me/R/ti/p/${encodeURIComponent(basicId)}`;
}
