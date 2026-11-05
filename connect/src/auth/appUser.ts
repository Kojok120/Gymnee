// アプリ（iOS）から Worker を呼ぶときの本人確認。アプリは Supabase のアクセストークンを Bearer で送る。
// Supabase Auth の /auth/v1/user に問い合わせて確かめる（失効・サインアウト済みのトークンも弾ける）。
// アプリ向けの口（/app/*）はこれでしか通さない。外部のトークン（OAuth・PAT）はここでは受けない。

import type { Env } from "../env.js";

export async function verifyAppUser(env: Env, request: Request, doFetch: typeof fetch = fetch): Promise<string | null> {
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  const token = match?.[1];
  // 外部向けのトークンをアプリの口に流用させない。
  if (!token || token.startsWith("gym_pat_") || token.split(".").length !== 3) return null;
  const res = await doFetch(`${env.SUPABASE_URL.replace(/\/$/, "")}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${token}` },
  });
  if (!res.ok) return null;
  const user = (await res.json()) as { id?: unknown; is_anonymous?: unknown };
  // 匿名認証は撤去済みだが、残っていても連携は使わせない（本人のアカウントに紐づけるため）。
  if (typeof user.id !== "string" || user.is_anonymous === true) return null;
  return user.id;
}
