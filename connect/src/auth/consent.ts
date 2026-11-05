// OAuth の承認画面（/authorize）。ログインの代わりに「iPhone の Gymnee で承認」してもらう。
//
// 流れ:
//  1. MCP のクライアント（Claude など）がブラウザでこの画面を開く。承認待ちの組（ペアリング）を作り、
//     2 桁の番号と、アプリを開くリンク（スマホならボタン、PC なら QR）を出す。
//  2. 利用者がアプリで開くと、アプリはサインイン済みの本人として承認待ちを読み、番号を見比べてから承認する。
//  3. この画面は承認を待ち（数秒おきに確かめる）、承認されたら自分でフォームを送り、トークンを発行して
//     クライアントへ戻す。承認の「フォームを送る」のは画面を開いたブラウザだけ（ライブラリの cookie で縛られる）。
//
// Gymnee の利用者の多くは Apple でサインインしていて、Web でのログインを用意できないため、この形にした（#171）。

import { AuthorizationError, CimdFetchError } from "@cloudflare/workers-oauth-provider";
import { renderSVG } from "uqr";
import type { Env } from "../env.js";
import type { Repo } from "../db/repo.js";
import { describeScopes, normalizeScopes } from "../domain/scopes.js";
import { randomToken } from "../domain/crypto.js";
import { authorizationServer, type AuthProps } from "./oauth.js";

const escape = (value: string) => value.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

function twoDigitCode(): string {
  const n = new Uint32Array(1);
  crypto.getRandomValues(n);
  return String(10 + (n[0]! % 90));
}

function securityHeaders(headers: Headers, nonce: string): Headers {
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("X-Frame-Options", "DENY");
  // form-action は付けない（承認後のリダイレクト先＝クライアントの URL まで縛ってしまうため）。
  headers.set(
    "Content-Security-Policy",
    `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; img-src data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'`,
  );
  return headers;
}

function page(nonce: string, title: string, body: string): string {
  return `<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${escape(title)}</title>
<style nonce="${nonce}">
  :root { --bg:#f6f7f4; --card:#ffffff; --text:#14160f; --muted:#5d6255; --line:#e1e4da; --accent:#1f2a0a; --lime:#c6ff3d; --warn:#8a3b12; }
  @media (prefers-color-scheme: dark) { :root { --bg:#0e0f0c; --card:#181a14; --text:#eef1e6; --muted:#a3a896; --line:#2b2e25; --accent:#c6ff3d; --warn:#ffb38a; } }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--text); font:16px/1.6 -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Noto Sans JP", sans-serif; }
  main { max-width:440px; margin:0 auto; padding:32px 16px 48px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:24px 20px; }
  h1 { font-size:20px; margin:0 0 8px; }
  p { margin:8px 0; }
  .muted { color:var(--muted); font-size:14px; }
  .warn { color:var(--warn); font-size:14px; }
  ul { padding-left:20px; margin:8px 0 16px; }
  .code { font-size:44px; font-weight:700; letter-spacing:0.1em; text-align:center; margin:12px 0 4px; font-variant-numeric:tabular-nums; }
  .qr { width:200px; height:200px; margin:12px auto; background:#fff; padding:8px; border-radius:12px; }
  .qr svg { width:100%; height:100%; display:block; }
  .btn { display:block; width:100%; text-align:center; padding:14px 16px; border-radius:12px; border:0; font-size:16px; font-weight:600; text-decoration:none; cursor:pointer; }
  .primary { background:var(--accent); color:var(--bg); }
  .secondary { background:transparent; color:var(--text); border:1px solid var(--line); margin-top:8px; }
  .status { text-align:center; margin-top:16px; font-size:14px; color:var(--muted); }
  .only-mobile { display:none; } .only-desktop { display:block; }
  @media (hover: none) and (pointer: coarse) { .only-mobile { display:block; } .only-desktop { display:none; } }
  hr { border:0; border-top:1px solid var(--line); margin:20px 0; }
</style>
</head>
<body><main><div class="card">${body}</div></main></body>
</html>`;
}

export function errorPage(message: string, status = 400): Response {
  const nonce = randomToken(12);
  const html = page(nonce, "Gymnee", `<h1>接続できませんでした</h1><p>${escape(message)}</p><p class="muted">接続を始めたアプリから、もう一度やり直してください。</p>`);
  return new Response(html, { status, headers: securityHeaders(new Headers(), nonce) });
}

/** GET /authorize: 承認待ちを作り、番号とアプリを開く手段を出す。 */
export async function showAuthorize(request: Request, env: Env, repo: Repo): Promise<Response> {
  const oauth = authorizationServer(env).getOAuthApi(env);
  try {
    const authRequest = await oauth.parseAuthRequest(request);
    const details = await oauth.describeConsent(authRequest);
    const consent = await oauth.beginConsent(authRequest);
    const scopes = normalizeScopes(details.scope);
    const pairing = await repo.createPairing({
      code: twoDigitCode(),
      client_name: details.clientName.slice(0, 120),
      client_domain: details.clientDomain ?? null,
      redirect_host: details.redirectHost.slice(0, 200),
      redirect_is_loopback: details.redirectIsLoopback,
      scopes,
    });
    const approveUrl = `${env.SITE_ORIGIN}/connect/approve?p=${pairing.id}`;
    const appUrl = `gymnee://connect/approve?p=${pairing.id}`;
    const nonce = randomToken(12);
    const origin = details.clientDomain
      ? `<p class="muted">提供元: <strong>${escape(details.clientDomain)}</strong></p>`
      : `<p class="muted">名前はアプリの自己申告です。</p>`;
    const loopback = details.redirectIsLoopback
      ? `<p class="warn">このパソコンの中のアプリに権限を渡します。自分で接続を始めたときだけ進めてください。</p>`
      : "";
    const body = `
      <h1>${escape(details.clientName)} を Gymnee につなぎますか</h1>
      ${origin}
      <p class="muted">権限を渡す先: <strong>${escape(details.redirectHost)}</strong></p>
      ${loopback}
      <p>できるようになること:</p>
      <ul>${describeScopes(scopes).map((s) => `<li>${escape(s.label)}</li>`).join("")}</ul>
      <hr>
      <p>iPhone の Gymnee で承認してください。アプリにも同じ番号が出ます。</p>
      <div class="code" aria-label="確認の番号">${pairing.code}</div>
      <div class="only-desktop">
        <div class="qr" role="img" aria-label="Gymnee を開く QR コード">${renderSVG(approveUrl, { border: 1 })}</div>
        <p class="muted" style="text-align:center">iPhone のカメラで読み取ると Gymnee が開きます。</p>
      </div>
      <div class="only-mobile">
        <a class="btn primary" href="${escape(approveUrl)}">Gymnee で承認する</a>
        <a class="btn secondary" href="${escape(appUrl)}">開かないときはこちら</a>
      </div>
      <form id="f" method="post" action="/authorize">
        <input type="hidden" name="handle" value="${escape(consent.handle)}">
        <input type="hidden" name="pairing" value="${escape(pairing.id)}">
        <p class="status" id="status">アプリでの承認を待っています…</p>
        <noscript><button class="btn secondary" type="submit">アプリで承認したら押す</button></noscript>
      </form>
      <p class="muted">このページを開いたのが自分でなければ、承認しないでください。10 分で切れます。</p>
      <script nonce="${nonce}">
        (function () {
          var id = ${JSON.stringify(pairing.id)};
          var deadline = Date.now() + 10 * 60 * 1000;
          var status = document.getElementById("status");
          function tick() {
            if (Date.now() > deadline) { status.textContent = "時間切れです。接続をやり直してください。"; return; }
            fetch("/authorize/pairing/" + id, { cache: "no-store" })
              .then(function (r) { return r.json(); })
              .then(function (d) {
                if (d.status === "approved" || d.status === "denied") {
                  status.textContent = d.status === "approved" ? "承認されました。戻ります…" : "拒否されました。";
                  document.getElementById("f").submit();
                } else if (d.status === "expired") {
                  status.textContent = "時間切れです。接続をやり直してください。";
                } else { setTimeout(tick, 2000); }
              })
              .catch(function () { setTimeout(tick, 4000); });
          }
          setTimeout(tick, 2000);
        })();
      </script>`;
    return new Response(page(nonce, `${details.clientName} を Gymnee につなぐ`, body), {
      headers: securityHeaders(consent.headers, nonce),
    });
  } catch (error) {
    if (error instanceof AuthorizationError && error.redirectTo) return Response.redirect(error.redirectTo, 302);
    if (error instanceof AuthorizationError) return errorPage(error.description);
    if (error instanceof CimdFetchError) return errorPage("接続しようとしたアプリを確かめられませんでした。");
    throw error;
  }
}

/** GET /authorize/pairing/:id: 承認されたかだけを返す（中身は返さない）。 */
export async function pairingStatus(id: string, repo: Repo): Promise<Response> {
  let status = "expired";
  try {
    const p = await repo.pairing(id);
    if (p) status = p.status;
  } catch {
    // 形の違う id など。切れた扱いにする。
  }
  return Response.json({ status }, { headers: { "Cache-Control": "no-store" } });
}

/** POST /authorize: アプリでの判断を受け取り、トークンを出してクライアントへ戻す。 */
export async function finishAuthorize(request: Request, env: Env, repo: Repo): Promise<Response> {
  const oauth = authorizationServer(env).getOAuthApi(env);
  const form = await request.formData();
  const handle = String(form.get("handle") ?? "");
  const pairingId = String(form.get("pairing") ?? "");
  try {
    const current = await repo.pairing(pairingId).catch(() => null);
    if (!current || current.status === "pending") {
      return errorPage("まだアプリで承認されていません。アプリで承認してから、このページに戻ってください。", 409);
    }
    const pairing = await repo.consumePairing(pairingId);
    if (!pairing) return errorPage("この承認はもう使われたか、時間切れです。", 410);

    if (current.status === "denied" || !current.user_id || !current.approved_scopes) {
      const denied = await oauth.denyConsent(request, handle);
      denied.headers.set("Location", denied.redirectTo);
      return new Response(null, { status: 302, headers: denied.headers });
    }

    // 権限は利用者がアプリで認めたものだけ。更新用のトークンはライブラリが offline_access の有無によらず出す。
    const scopes = normalizeScopes(current.approved_scopes);
    const approved = await oauth.approveConsent(request, handle, { scope: scopes });
    const finalScopes = scopes;
    const props: AuthProps = { userId: current.user_id, scopes, via: "oauth" };
    const { redirectTo } = await oauth.completeAuthorization({
      request: approved.request,
      userId: current.user_id,
      metadata: { clientName: current.client_name, clientDomain: current.client_domain, approvedAt: new Date().toISOString() },
      scope: finalScopes,
      props,
    });
    approved.headers.set("Location", redirectTo);
    return new Response(null, { status: 302, headers: approved.headers });
  } catch (error) {
    if (error instanceof AuthorizationError) return errorPage(error.description);
    throw error;
  }
}
