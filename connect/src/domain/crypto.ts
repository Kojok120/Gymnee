// 暗号まわりの小さな部品。Web Crypto だけで書き、Workers と Node (vitest) の両方で動かす。

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function bytesToBase64(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

export function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function base64Url(bytes: Uint8Array): string {
  return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64UrlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  return base64ToBytes(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
}

/** 推測できない乱数の文字列（base64url）。 */
export function randomToken(byteLength = 32): string {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmacKey(secret: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function hmacSha256(secret: Uint8Array | string, data: string): Promise<Uint8Array> {
  const key = await hmacKey(typeof secret === "string" ? encoder.encode(secret) : secret);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(data)));
}

/** 長さに依存しない比較（署名の照合に使う）。 */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ---- 送り先 URL などの暗号化（AES-256-GCM） ----
// DB には暗号文だけを置く。Slack / Discord の Webhook URL はそれ自体が投稿の鍵なので平文で持たない。

async function aesKey(base64Key: string): Promise<CryptoKey> {
  const raw = base64ToBytes(base64Key);
  if (raw.length !== 32) throw new Error("ENCRYPTION_KEY は 32 バイトの base64 にする");
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function encryptString(base64Key: string, plaintext: string): Promise<string> {
  const iv = new Uint8Array(12);
  crypto.getRandomValues(iv);
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await aesKey(base64Key), encoder.encode(plaintext));
  return `v1.${base64Url(iv)}.${base64Url(new Uint8Array(ct))}`;
}

export async function decryptString(base64Key: string, sealed: string): Promise<string> {
  const [version, ivPart, ctPart] = sealed.split(".");
  if (version !== "v1" || !ivPart || !ctPart) throw new Error("暗号文の形式が違う");
  const pt = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64UrlToBytes(ivPart) },
    await aesKey(base64Key),
    base64UrlToBytes(ctPart),
  );
  return decoder.decode(pt);
}

// ---- 署名付きの state（LINE / Slack / Discord の OAuth の往復で使う） ----
// 中身は「誰が・何のために・いつまで」。改ざんと使い回し（期限）を防ぐ。

export interface SignedState {
  /** Gymnee のユーザー id。 */
  u: string;
  /** 用途（line / slack / discord）。別の用途の state を流用させない。 */
  k: string;
  /** 期限（UNIX 秒）。 */
  exp: number;
  /** 乱数。同じ内容でも毎回違う値にする。 */
  n: string;
}

export async function signState(secret: string, state: Omit<SignedState, "n">): Promise<string> {
  const body = base64Url(encoder.encode(JSON.stringify({ ...state, n: randomToken(12) })));
  const sig = base64Url(await hmacSha256(secret, body));
  return `${body}.${sig}`;
}

export async function verifyState(
  secret: string,
  token: string,
  expectedKind: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<SignedState | null> {
  const [body, sig] = token.split(".");
  if (!body || !sig) return null;
  const expected = base64Url(await hmacSha256(secret, body));
  if (!timingSafeEqual(sig, expected)) return null;
  try {
    const state = JSON.parse(decoder.decode(base64UrlToBytes(body))) as SignedState;
    if (state.k !== expectedKind || typeof state.u !== "string" || state.exp < nowSeconds) return null;
    return state;
  } catch {
    return null;
  }
}
