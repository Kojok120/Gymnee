// フレンドのチェックイン通知を APNs 経由で送る Edge Function（§6.10 / §6.11）。
// DB トリガー `notify_friend_checkin` から { event, visitId } を受け取り、
// 訪問者のフォロワー全員の device_tokens へ「〇〇さんがジムに行きました」を送信する。
//
// 必要なシークレット（`supabase secrets set ...`）:
//   APNS_KEY            … AuthKey_XXXX.p8 の中身全文（-----BEGIN PRIVATE KEY----- を含む。改行は実改行/\n どちらでも可）
//   APNS_KEY_ID         … APNs Auth Key の Key ID（10桁）
//   APNS_TEAM_ID        … Apple Team ID（例: PG5P26J3W2）
//   APNS_BUNDLE_ID      … com.gymnee.app（既定値あり）
//   APNS_HOST           … api.sandbox.push.apple.com（dev署名/Xcodeデバッグ）または api.push.apple.com（配布）
//   PUSH_SHARED_SECRET  … DB トリガーと共有する任意の秘密。X-Push-Secret の照合に使う
// 自動注入（Supabase が付与）: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APNS_KEY = Deno.env.get("APNS_KEY") ?? "";
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "com.gymnee.app";
const APNS_HOST = Deno.env.get("APNS_HOST") ?? "api.sandbox.push.apple.com";
const PUSH_SHARED_SECRET = Deno.env.get("PUSH_SHARED_SECRET") ?? "";

function base64UrlFromBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function base64UrlFromString(str: string): string {
  return base64UrlFromBytes(new TextEncoder().encode(str));
}

/// .p8(PEM, PKCS#8) を ECDSA P-256 の署名鍵として取り込む。
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

/// APNs プロバイダ認証トークン（ES256 JWT）。最大1時間有効だが毎回生成で十分。
async function makeProviderToken(): Promise<string> {
  const header = { alg: "ES256", kid: APNS_KEY_ID };
  const payload = { iss: APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) };
  const signingInput =
    `${base64UrlFromString(JSON.stringify(header))}.${base64UrlFromString(JSON.stringify(payload))}`;
  const key = await importPrivateKey(APNS_KEY.replace(/\\n/g, "\n"));
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  // Web Crypto の ECDSA は ES256 が要求する r||s 形式（IEEE P1363）で返るため、そのまま使える。
  return `${signingInput}.${base64UrlFromBytes(new Uint8Array(sig))}`;
}

Deno.serve(async (req) => {
  // DB トリガー以外からの呼び出しを拒否（共有シークレット照合）。
  if (PUSH_SHARED_SECRET && req.headers.get("X-Push-Secret") !== PUSH_SHARED_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  let payload: { event?: string; visitId?: string };
  try {
    payload = await req.json();
  } catch {
    return new Response("bad request", { status: 400 });
  }
  const visitId = payload.visitId;
  if (!visitId) return new Response("missing visitId", { status: 400 });

  const db = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });

  // 訪問・訪問者名・ジム名。
  const { data: visit } = await db
    .from("visits").select("user_id, gym_id").eq("id", visitId).single();
  if (!visit) return new Response(JSON.stringify({ sent: 0, reason: "visit not found" }), { status: 200 });

  const visitorId = visit.user_id as string;
  const [{ data: profile }, gymRes] = await Promise.all([
    db.from("profiles").select("display_name").eq("id", visitorId).single(),
    visit.gym_id
      ? db.from("gyms").select("name").eq("id", visit.gym_id).single()
      : Promise.resolve({ data: null }),
  ]);
  const visitorName = profile?.display_name ?? "フレンド";
  const gymName = (gymRes.data as { name?: string } | null)?.name;

  // フォロワー（followee_id = 訪問者）の端末トークンを集める。
  const { data: followers } = await db
    .from("follows").select("follower_id").eq("followee_id", visitorId);
  const followerIds = (followers ?? []).map((r) => r.follower_id as string);
  if (followerIds.length === 0) return new Response(JSON.stringify({ sent: 0 }), { status: 200 });

  const { data: tokens } = await db
    .from("device_tokens").select("token").in("user_id", followerIds);
  const deviceTokens = (tokens ?? []).map((r) => r.token as string);
  if (deviceTokens.length === 0) return new Response(JSON.stringify({ sent: 0 }), { status: 200 });

  const providerToken = await makeProviderToken();
  const title = `${visitorName}さんがジムに行きました`;
  const message = gymName ? `${gymName} にチェックイン💪` : "チェックインしました💪";
  const apsBody = JSON.stringify({
    aps: { alert: { title, body: message }, sound: "default" },
    type: "friend_checkin",
    visitorId,
  });

  let sent = 0;
  const stale: string[] = [];
  await Promise.all(deviceTokens.map(async (token) => {
    const res = await fetch(`https://${APNS_HOST}/3/device/${token}`, {
      method: "POST",
      headers: {
        "authorization": `bearer ${providerToken}`,
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "content-type": "application/json",
      },
      body: apsBody,
    });
    if (res.status === 200) {
      sent++;
    } else if (res.status === 410) {
      stale.push(token); // BadDeviceToken/Unregistered → 後で掃除
    } else {
      console.error(`APNs ${res.status} for token ${token.slice(0, 8)}…: ${await res.text()}`);
    }
  }));

  // 失効トークンの掃除（アンインストール端末など）。
  if (stale.length > 0) {
    await db.from("device_tokens").delete().in("token", stale);
  }

  return new Response(JSON.stringify({ sent, stale: stale.length }), {
    headers: { "content-type": "application/json" },
  });
});
