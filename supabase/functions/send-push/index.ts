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

// deno-lint-ignore no-explicit-any
type DB = any;

/// 指定ユーザー群の端末トークンへ APNs 送信。失効(410)は掃除。送信数を返す。
async function pushToUsers(
  db: DB, userIds: string[], title: string, message: string, extra: Record<string, unknown>,
): Promise<number> {
  if (userIds.length === 0) return 0;
  const { data: tokens } = await db.from("device_tokens").select("token").in("user_id", userIds);
  const deviceTokens = (tokens ?? []).map((r: { token: string }) => r.token);
  if (deviceTokens.length === 0) return 0;

  // 鍵未設定/不正PEM等で例外を出さず縮退（push_config 設定済みでAPNS鍵だけ未設定の運用ズレ対策）。
  let providerToken: string;
  try {
    providerToken = await makeProviderToken();
  } catch (e) {
    console.error("APNs token生成失敗（鍵未設定/不正の可能性）:", String(e));
    return 0;
  }
  const apsBody = JSON.stringify({ aps: { alert: { title, body: message }, sound: "default" }, ...extra });
  let sent = 0;
  const stale: string[] = [];
  // fetch のネットワーク例外で全体が落ちないよう allSettled＋個別try/catch。
  await Promise.allSettled(deviceTokens.map(async (token: string) => {
    try {
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
      if (res.status === 200) sent++;
      else if (res.status === 410 || res.status === 400) stale.push(token); // 失効/不正トークンは掃除
      else console.error(`APNs ${res.status} for token ${token.slice(0, 8)}…: ${await res.text()}`);
    } catch (e) {
      console.error(`APNs fetch失敗 token ${token.slice(0, 8)}…: ${String(e)}`);
    }
  }));
  if (stale.length > 0) await db.from("device_tokens").delete().in("token", stale);
  return sent;
}

Deno.serve(async (req) => {
  // DB トリガー以外からの呼び出しを拒否（共有シークレット照合）。
  if (PUSH_SHARED_SECRET && req.headers.get("X-Push-Secret") !== PUSH_SHARED_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  let payload: { event?: string; visitId?: string; reactionId?: string; commentId?: string };
  try {
    payload = await req.json();
  } catch {
    return new Response("bad request", { status: 400 });
  }

  const db = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
  const event = payload.event ?? "friend_checkin";

  // --- いいね → 投稿者へ通知 ---
  if (event === "reaction") {
    const reactionId = payload.reactionId;
    if (!reactionId) return new Response("missing reactionId", { status: 400 });
    const { data: reaction } = await db
      .from("post_reactions").select("user_id, feed_item_id, kind").eq("id", reactionId).single();
    if (!reaction) return new Response(JSON.stringify({ sent: 0, reason: "reaction not found" }), { status: 200 });
    const reactorId = reaction.user_id as string;
    const { data: item } = await db
      .from("feed_items").select("user_id").eq("id", reaction.feed_item_id).single();
    if (!item) return new Response(JSON.stringify({ sent: 0, reason: "feed_item not found" }), { status: 200 });
    const authorId = item.user_id as string;
    if (authorId === reactorId) return new Response(JSON.stringify({ sent: 0, reason: "self" }), { status: 200 });

    // 投稿者が「いいね通知」をオフにしていたら送らない（列が無い場合は既定で送る）。
    const { data: authorPref } = await db.from("profiles").select("notify_likes").eq("id", authorId).single();
    if (authorPref && authorPref.notify_likes === false) {
      return new Response(JSON.stringify({ sent: 0, reason: "muted" }), { status: 200 });
    }

    const { data: profile } = await db.from("profiles").select("display_name").eq("id", reactorId).single();
    const reactorName = profile?.display_name ?? "フレンド";
    // 筋トレ絵文字リアクション（like/strong/fire/clap）に応じて文面を変える。
    const kind = (reaction.kind as string) ?? "like";
    const emoji = kind === "fire" ? "🔥" : kind === "strong" ? "💪" : kind === "clap" ? "👏" : "❤️";
    const verb = kind === "like" ? "いいね" : "応援";
    const title = `${reactorName}さんが${verb}しました`;
    const message = `あなたの投稿に${emoji}`;
    const sent = await pushToUsers(db, [authorId], title, message, {
      type: "reaction", feedItemId: reaction.feed_item_id,
    });
    return new Response(JSON.stringify({ sent }), { headers: { "content-type": "application/json" } });
  }

  // --- コメント → 投稿者へ通知 ---
  if (event === "comment") {
    const commentId = payload.commentId;
    if (!commentId) return new Response("missing commentId", { status: 400 });
    const { data: comment } = await db
      .from("comments").select("user_id, feed_item_id, text").eq("id", commentId).single();
    if (!comment) return new Response(JSON.stringify({ sent: 0, reason: "comment not found" }), { status: 200 });
    const commenterId = comment.user_id as string;
    const { data: item } = await db
      .from("feed_items").select("user_id").eq("id", comment.feed_item_id).single();
    if (!item) return new Response(JSON.stringify({ sent: 0, reason: "feed_item not found" }), { status: 200 });
    const authorId = item.user_id as string;
    if (authorId === commenterId) return new Response(JSON.stringify({ sent: 0, reason: "self" }), { status: 200 });

    // 投稿者が「コメント通知」をオフにしていたら送らない（列が無い場合は既定で送る）。
    const { data: authorPref } = await db.from("profiles").select("notify_comments").eq("id", authorId).single();
    if (authorPref && authorPref.notify_comments === false) {
      return new Response(JSON.stringify({ sent: 0, reason: "muted" }), { status: 200 });
    }

    const { data: profile } = await db.from("profiles").select("display_name").eq("id", commenterId).single();
    const commenterName = profile?.display_name ?? "フレンド";
    const preview = ((comment.text as string) ?? "").slice(0, 40);
    const title = `${commenterName}さんがコメントしました`;
    const message = preview.length > 0 ? preview : "あなたの投稿にコメント💬";
    const sent = await pushToUsers(db, [authorId], title, message, {
      type: "comment", feedItemId: comment.feed_item_id,
    });
    return new Response(JSON.stringify({ sent }), { headers: { "content-type": "application/json" } });
  }

  // --- フレンドのチェックイン → フォロワーへ通知（既定） ---
  const visitId = payload.visitId;
  if (!visitId) return new Response("missing visitId", { status: 400 });

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

  // notify=true のフォロワーにのみ送る（フレンドごとの通知ON/OFF設定を尊重）。
  const { data: followers } = await db
    .from("follows").select("follower_id").eq("followee_id", visitorId).eq("notify", true);
  let followerIds = (followers ?? []).map((r: { follower_id: string }) => r.follower_id);

  // 受信者側の「フレンドのチェックイン通知」設定（profiles.notify_friend_checkin）を尊重。
  // 列が無い/未取得の場合は既定で送る。
  if (followerIds.length > 0) {
    const { data: prefs } = await db
      .from("profiles").select("id, notify_friend_checkin").in("id", followerIds);
    const muted = new Set(
      (prefs ?? [])
        .filter((p: { notify_friend_checkin?: boolean }) => p.notify_friend_checkin === false)
        .map((p: { id: string }) => p.id),
    );
    followerIds = followerIds.filter((id: string) => !muted.has(id));
  }

  const title = `${visitorName}さんがジムに行きました`;
  const message = gymName ? `${gymName} にチェックイン💪` : "チェックインしました💪";
  const sent = await pushToUsers(db, followerIds, title, message, {
    type: "friend_checkin", visitorId,
  });
  return new Response(JSON.stringify({ sent }), { headers: { "content-type": "application/json" } });
});
