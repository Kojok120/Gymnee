// 汎用 Webhook の署名（Standard Webhooks: https://www.standardwebhooks.com/）。
// webhook-id / webhook-timestamp / webhook-signature の 3 つのヘッダーを付ける。
// 署名は base64(HMAC-SHA256(鍵, "<id>.<timestamp>.<本文>"))、鍵は whsec_ の後ろを base64 で読んだもの。

import { base64ToBytes, bytesToBase64, hmacSha256 } from "./crypto.js";

export const SECRET_PREFIX = "whsec_";

export function generateWebhookSecret(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return `${SECRET_PREFIX}${bytesToBase64(bytes)}`;
}

export async function sign(secret: string, id: string, timestampSeconds: number, body: string): Promise<string> {
  const key = base64ToBytes(secret.startsWith(SECRET_PREFIX) ? secret.slice(SECRET_PREFIX.length) : secret);
  const mac = await hmacSha256(key, `${id}.${timestampSeconds}.${body}`);
  return `v1,${bytesToBase64(mac)}`;
}

export async function signedHeaders(secret: string, id: string, timestampSeconds: number, body: string): Promise<Record<string, string>> {
  return {
    "webhook-id": id,
    "webhook-timestamp": String(timestampSeconds),
    "webhook-signature": await sign(secret, id, timestampSeconds, body),
  };
}
