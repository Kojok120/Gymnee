// ローカルでの通し確認（#171）。ローカル Supabase と `wrangler dev --env local` を立ててから流す。
//   node scripts/e2e-local.mjs
// 1. ローカルの Auth で検証用の利用者を作り、アプリと同じトークンを得る
// 2. アプリの口で API キー（PAT）を作る
// 3. PAT で REST を読む・記録を足す（冪等・自己ベスト）
// 4. PAT で MCP を呼ぶ
// 4.5 送り先（汎用 Webhook）を足し、記録の完了が届くまで（cron を手で呼ぶ）
// 5. OAuth（DCR → 承認画面 → アプリで承認 → トークン）で MCP を呼ぶ
// 6. 後片付け（作った利用者を消す。記録は連鎖削除）
import { createHash, randomBytes } from "node:crypto";
import { execFileSync } from "node:child_process";

const WORKER = process.env.WORKER ?? "http://localhost:8787";
const status = JSON.parse(execFileSync("supabase", ["status", "--output-format", "json"], { cwd: new URL("../../", import.meta.url).pathname, encoding: "utf8" }));
const SB = status.env.API_URL;
const PUB = status.env.PUBLISHABLE_KEY;
const SECRET = status.env.SECRET_KEY;
const DB_URL = status.env.DB_URL;
const PSQL = process.env.PSQL ?? "/opt/homebrew/opt/postgresql@16/bin/psql";
const sql = (q) => execFileSync(PSQL, [DB_URL, "-tAX", "-c", q], { encoding: "utf8" }).trim();
// 汎用 Webhook の確かめに使う、公開の受け口（POST に 200 を返すもの）
const ECHO_URL = process.env.ECHO_URL ?? "https://httpbin.org/post";

let failures = 0;
function check(label, ok, detail) {
  console.log(`${ok ? "OK  " : "NG  "} ${label}${ok || detail === undefined ? "" : `\n     ${typeof detail === "string" ? detail : JSON.stringify(detail).slice(0, 400)}`}`);
  if (!ok) failures += 1;
}

async function j(res) {
  const text = await res.text();
  try { return JSON.parse(text); } catch { return text; }
}

// ---- 1. 利用者 ----
const email = `connect-e2e-${Date.now()}@example.com`;
const signup = await fetch(`${SB}/auth/v1/admin/users`, {
  method: "POST",
  headers: { apikey: SECRET, Authorization: `Bearer ${SECRET}`, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password: "e2e-password-123", email_confirm: true }),
}).then(j);
const userId = signup.id;
check("ローカルに検証用の利用者を作る", typeof userId === "string", signup);
const session = await fetch(`${SB}/auth/v1/token?grant_type=password`, {
  method: "POST",
  headers: { apikey: PUB, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password: "e2e-password-123" }),
}).then(j);
const jwt = session.access_token;
check("アプリと同じアクセストークンを得る", typeof jwt === "string", session);

const app = (path, init = {}) =>
  fetch(`${WORKER}/app${path}`, { ...init, headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json", ...(init.headers ?? {}) } });

try {
  // ---- 2. PAT ----
  check("アプリの口はトークン無しで 401", (await fetch(`${WORKER}/app/connections`)).status === 401);
  const created = await app("/tokens", { method: "POST", body: JSON.stringify({ name: "e2e", scopes: ["workouts:write"] }) }).then(j);
  const pat = created.token;
  check("PAT を作る（read は自動で付く）", typeof pat === "string" && pat.startsWith("gym_pat_") && created.scopes.length === 2, created);
  const connections = await app("/connections").then(j);
  check("連携の一覧に PAT が出る（トークンそのものは出ない）", connections.apiTokens?.length === 1 && !JSON.stringify(connections).includes(pat), connections);

  const api = (path, init = {}) =>
    fetch(`${WORKER}${path}`, { ...init, headers: { Authorization: `Bearer ${pat}`, "Content-Type": "application/json", ...(init.headers ?? {}) } });

  // ---- 3. REST ----
  const unauth = await fetch(`${WORKER}/v1/summary`);
  check("REST はトークン無しで 401 と resource_metadata", unauth.status === 401 && (unauth.headers.get("www-authenticate") ?? "").includes("resource_metadata"), unauth.headers.get("www-authenticate"));
  const summary = await api("/v1/summary").then(j);
  check("summary を読む", summary.data?.weeklyGoal === 3 && summary.data?.thisWeek?.workouts === 0, summary);
  const exercises = await api("/v1/exercises?q=ベンチ").then(j);
  check("種目を名前で探す", Array.isArray(exercises.data) && exercises.data.some((e) => e.name === "ベンチプレス"), exercises);

  const body = JSON.stringify({ name: "胸の日", durationMinutes: 40, exercises: [{ name: "ベンチプレス", sets: [{ weightKg: 60, reps: 10 }, { weightKg: 62.5, reps: 8 }] }, { name: "腕立て伏せ", sets: [{ reps: 20 }] }] });
  const first = await api("/v1/workouts", { method: "POST", body, headers: { "Idempotency-Key": "e2e-key-0001" } });
  const firstBody = await j(first);
  check("記録を足す（201・自己ベストつき）", first.status === 201 && firstBody.data?.personalRecords?.length > 0, firstBody);
  const again = await api("/v1/workouts", { method: "POST", body, headers: { "Idempotency-Key": "e2e-key-0001" } });
  const againBody = await j(again);
  check("同じ鍵の再送は増やさない（200・同じ id）", again.status === 200 && againBody.data?.workoutId === firstBody.data?.workoutId && againBody.data?.created === false, againBody);
  const listed = await api("/v1/workouts").then(j);
  check("足した記録が一覧に出る（1 件・セットつき）", listed.data?.length === 1 && listed.data[0].exercises[0].sets.length === 2, listed);
  const one = await api(`/v1/workouts/${firstBody.data?.workoutId}`).then(j);
  check("記録を 1 件読む", one.data?.name === "胸の日" && one.data?.durationSeconds === 2400, one);
  const prs = await api("/v1/personal-records").then(j);
  check("自己ベストが入る", prs.data?.some((p) => p.type === "max_weight" && p.value === 62.5), prs);
  const after = await api("/v1/summary").then(j);
  check("summary に反映される", after.data?.thisWeek?.workouts === 1 && after.data?.recordedToday === true, after);
  const ambiguous = await api("/v1/workouts", { method: "POST", body: JSON.stringify({ exercises: [{ name: "ベンチ", sets: [{ weightKg: 60, reps: 10 }] }] }) });
  const ambiguousBody = await j(ambiguous);
  check("種目が決まらなければ 422 と候補", ambiguous.status === 422 && ambiguousBody.error?.details?.[0]?.candidates?.length > 0, ambiguousBody);
  const proposal = await api("/v1/coach/proposals", { method: "POST", body: JSON.stringify({ title: "胸", message: "x", exercises: [{ name: "ベンチプレス", sets: 3, reps: 8, weightKg: 60 }] }) });
  check("coach:write の無い PAT で提案すると 403", proposal.status === 403, await j(proposal));

  // ---- 4. MCP（PAT） ----
  const mcp = (token, payload) =>
    fetch(`${WORKER}/mcp`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", Accept: "application/json, text/event-stream", "Mcp-Protocol-Version": "2025-11-25" },
      body: JSON.stringify(payload),
    }).then(j);
  const init = await mcp(pat, { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "e2e", version: "1" } } });
  check("MCP initialize", init.result?.serverInfo?.name === "gymnee", init);
  const tools = await mcp(pat, { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} });
  const toolNames = tools.result?.tools?.map((t) => t.name) ?? [];
  check("MCP の道具は権限ぶんだけ（log_workout あり・propose_menu なし）", toolNames.includes("log_workout") && !toolNames.includes("propose_menu"), toolNames);
  const called = await mcp(pat, { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "get_summary", arguments: {} } });
  check("MCP で get_summary を呼ぶ", called.result?.content?.[0]?.text?.includes("weeklyGoal"), called);

  // ---- 4.5 送り先と配信 ----
  const added = await app("/destinations", { method: "POST", body: JSON.stringify({ url: ECHO_URL, label: "e2e" }) });
  const addedBody = await j(added);
  check("汎用 Webhook を足す（確かめの 1 通が届き、署名の鍵が 1 回だけ返る）", added.status === 201 && addedBody.signingSecret?.startsWith("whsec_"), addedBody);
  const destId = addedBody.destination?.id;
  const conn2 = await app("/connections").then(j);
  const conn2Text = JSON.stringify(conn2);
  check("一覧に送り先が出る（URL と鍵は出さない）", conn2.destinations?.length === 1 && !conn2Text.includes(ECHO_URL) && !conn2Text.includes(addedBody.signingSecret ?? "@@"), conn2.destinations);
  const unreachable = await app("/destinations", { method: "POST", body: JSON.stringify({ url: "https://httpbin.org/status/410" }) });
  check("届かない URL は足さない（422）", unreachable.status === 422, await j(unreachable));
  const internal = await app("/destinations", { method: "POST", body: JSON.stringify({ url: "https://127.0.0.1/hook" }) });
  check("内部の宛先は断る（422）", internal.status === 422, await j(internal));
  const stored = sql(`select target_ciphertext from public.connect_destinations where id = '${destId}'`);
  check("送り先の URL は暗号化して保存する", stored.startsWith("v1.") && !stored.includes("httpbin"), stored.slice(0, 40));

  const logged = await api("/v1/workouts", { method: "POST", body: JSON.stringify({ name: "配信の確認", exercises: [{ name: "ベンチプレス", sets: [{ weightKg: 50, reps: 5 }] }] }) }).then(j);
  const wid = logged.data?.workoutId;
  check("記録を足すと知らせが積まれる（2 分待ってから送る）", sql(`select count(*) from public.connect_events where subject_id = '${wid}' and process_after > now()`) === "1");
  sql(`update public.connect_events set process_after = now() - interval '1 second' where subject_id = '${wid}'`);
  let scheduled = await fetch(`${WORKER}/cdn-cgi/handler/scheduled?cron=*+*+*+*+*`);
  if (scheduled.status === 404) scheduled = await fetch(`${WORKER}/__scheduled?cron=*+*+*+*+*`);
  let delivery = "";
  for (let i = 0; i < 20; i++) {
    delivery = sql(`select status || ':' || coalesce(last_status::text, '-') from public.connect_deliveries where subject_id = '${wid}'`);
    if (delivery && !delivery.startsWith("pending")) break;
    await new Promise((r) => setTimeout(r, 1000));
  }
  check("cron で送り先に届く（succeeded:200）", delivery === "succeeded:200", { scheduled: scheduled.status, delivery });
  const patched = await app(`/destinations/${destId}`, { method: "PATCH", body: JSON.stringify({ events: ["weekly.summary"] }) }).then(j);
  check("送る内容を変える", JSON.stringify(patched.destination?.events) === '["weekly.summary"]', patched);
  const removed = await app(`/destinations/${destId}`, { method: "DELETE" });
  check("送り先を消す", removed.status === 204 && (await app("/connections").then(j)).destinations?.length === 0);

  // ---- 5. OAuth ----
  const prm = await fetch(`${WORKER}/.well-known/oauth-protected-resource/mcp`).then(j);
  check("保護されたリソースの説明（RFC 9728）", prm.resource === `${WORKER}/mcp` && prm.authorization_servers?.[0] === WORKER, prm);
  const asm = await fetch(`${WORKER}/.well-known/oauth-authorization-server`).then(j);
  check("認可サーバーの説明（RFC 8414）", asm.registration_endpoint && asm.code_challenge_methods_supported?.includes("S256"), asm);
  const redirectUri = "http://127.0.0.1:9999/callback";
  const reg = await fetch(asm.registration_endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ client_name: "E2E Client", redirect_uris: [redirectUri], token_endpoint_auth_method: "none", grant_types: ["authorization_code", "refresh_token"], response_types: ["code"] }),
  }).then(j);
  check("クライアントを動的に登録（DCR）", typeof reg.client_id === "string", reg);

  const verifier = randomBytes(32).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  const authUrl = new URL(asm.authorization_endpoint);
  for (const [k, v] of Object.entries({ response_type: "code", client_id: reg.client_id, redirect_uri: redirectUri, code_challenge: challenge, code_challenge_method: "S256", state: "st-123", scope: "read coach:write", resource: `${WORKER}/mcp` })) authUrl.searchParams.set(k, v);
  const page = await fetch(authUrl, { redirect: "manual" });
  const html = await page.text();
  const cookies = (page.headers.getSetCookie?.() ?? []).map((c) => c.split(";")[0]).join("; ");
  const pairingId = /name="pairing" value="([^"]+)"/.exec(html)?.[1];
  const handle = /name="handle" value="([^"]+)"/.exec(html)?.[1];
  const code = /aria-label="確認の番号">(\d+)</.exec(html)?.[1];
  check("承認画面: 番号と QR と待ちのフォーム", page.status === 200 && pairingId && handle && code && html.includes("<svg") && html.includes("E2E Client"), html.slice(0, 300));

  const waiting = await fetch(`${WORKER}/authorize/pairing/${pairingId}`).then(j);
  check("承認前は pending", waiting.status === "pending", waiting);
  const early = await fetch(`${WORKER}/authorize`, { method: "POST", headers: { Cookie: cookies, "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ handle, pairing: pairingId }), redirect: "manual" });
  check("承認前にフォームを送っても進まない（409）", early.status === 409);

  const detail = await app(`/oauth/pairings/${pairingId}`).then(j);
  check("アプリが承認待ちを読む（同じ番号）", detail.code === code && detail.clientName === "E2E Client" && detail.scopes?.length === 2, detail);
  const decided = await app(`/oauth/pairings/${pairingId}`, { method: "POST", body: JSON.stringify({ decision: "approve", scopes: ["read"] }) }).then(j);
  check("アプリで承認（coach:write は外す）", decided.status === "approved" && decided.scopes?.length === 1, decided);
  const twice = await app(`/oauth/pairings/${pairingId}`, { method: "POST", body: JSON.stringify({ decision: "deny" }) });
  check("決まった承認は上書きできない（410）", twice.status === 410);

  const done = await fetch(`${WORKER}/authorize`, { method: "POST", headers: { Cookie: cookies, "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ handle, pairing: pairingId }), redirect: "manual" });
  const location = done.headers.get("location") ?? "";
  const authCode = new URL(location, WORKER).searchParams.get("code");
  check("承認後のフォームでクライアントへ戻る（code・state つき）", done.status === 302 && location.startsWith(redirectUri) && authCode && location.includes("state=st-123"), { status: done.status, location });
  const reuse = await fetch(`${WORKER}/authorize`, { method: "POST", headers: { Cookie: cookies, "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ handle, pairing: pairingId }), redirect: "manual" });
  check("同じ承認は 2 回使えない", reuse.status !== 302);

  const token = await fetch(asm.token_endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "authorization_code", code: authCode, redirect_uri: redirectUri, client_id: reg.client_id, code_verifier: verifier, resource: `${WORKER}/mcp` }),
  }).then(j);
  check("トークンに引き換える（read だけ）", typeof token.access_token === "string" && typeof token.refresh_token === "string" && token.scope === "read", token);
  const oauthTools = await mcp(token.access_token, { jsonrpc: "2.0", id: 9, method: "tools/list", params: {} });
  const oauthNames = oauthTools.result?.tools?.map((t) => t.name) ?? [];
  check("OAuth のトークンで MCP（読む道具だけ）", oauthNames.includes("get_summary") && !oauthNames.includes("propose_menu") && !oauthNames.includes("log_workout"), oauthNames);
  const restWithMcpToken = await fetch(`${WORKER}/v1/summary`, { headers: { Authorization: `Bearer ${token.access_token}` } });
  check("/mcp 用のトークンは /v1 では使えない（宛先が違う）", restWithMcpToken.status === 401);

  const listedGrants = await app("/connections").then(j);
  const grant = listedGrants.aiClients?.[0];
  check("連携の一覧に AI の接続が出る", grant?.name === "E2E Client", listedGrants.aiClients);
  await app(`/grants/${grant?.id}`, { method: "DELETE" });
  const afterRevoke = await mcp(token.access_token, { jsonrpc: "2.0", id: 10, method: "tools/list", params: {} });
  check("解除したらそのトークンは使えない", afterRevoke?.result === undefined, afterRevoke);

  await app(`/tokens/${created.id}`, { method: "DELETE" });
  check("PAT を失効したら使えない", (await api("/v1/summary")).status === 401);
} finally {
  // ---- 6. 後片付け ----
  await fetch(`${SB}/auth/v1/admin/users/${userId}`, { method: "DELETE", headers: { apikey: SECRET, Authorization: `Bearer ${SECRET}` } });
}

console.log(failures === 0 ? "\nすべて OK" : `\nNG が ${failures} 件`);
process.exit(failures === 0 ? 0 : 1);
