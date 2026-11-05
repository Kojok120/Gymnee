// iOS アプリ向けの口（/app/*）。アプリのサインイン（Supabase のアクセストークン）でだけ通す。
// 連携の一覧・API キー（PAT）の作成と失効・AI の接続（OAuth の許可）の承認と解除を受け持つ。

import { Hono } from "hono";
import { z } from "zod";
import type { Env } from "../env.js";
import { Postgrest } from "../db/postgrest.js";
import { Repo } from "../db/repo.js";
import { verifyAppUser } from "../auth/appUser.js";
import { authorizationServer, resourceUrls } from "../auth/oauth.js";
import { generatePat } from "../auth/pat.js";
import { describeScopes, normalizeScopes } from "../domain/scopes.js";
import { checkDestinationUrl } from "../domain/destinationUrl.js";
import { decryptString, encryptString } from "../domain/crypto.js";
import { generateWebhookSecret } from "../domain/standardWebhooks.js";
import { authorizeUrl, providerConfigured, type ChatProvider } from "../integrations/chatOAuth.js";
import { sendHello } from "../jobs/deliver.js";
import type { DestinationRow, LineLinkRow } from "../db/repo.js";
import { addFriendUrl, lineConfigured, linkMessageUrl } from "../integrations/line.js";

type AppEnv = { Bindings: Env; Variables: { userId: string; repo: Repo } };

/** 1 人が持てる API キーの数（作りっぱなしを防ぐ）。 */
const MAX_TOKENS_PER_USER = 10;
/** 1 人が持てる送り先の数。 */
export const MAX_DESTINATIONS_PER_USER = 10;
const EVENT_NAMES = ["workout.completed", "weekly.summary"] as const;

const CreateDestinationInput = z
  .object({
    url: z.string().min(1).max(2048),
    label: z.string().trim().min(1).max(60).optional(),
    events: z.array(z.enum(EVENT_NAMES)).min(1).max(2).optional(),
  })
  .strict();

const UpdateLineInput = z
  .object({
    notifyMode: z.enum(["off", "lapse", "daily", "daily_menu"]).optional(),
    notifyHour: z.number().int().min(0).max(23).optional(),
  })
  .strict();

export function lineView(env: Env, link: LineLinkRow | null) {
  const basicId = env.LINE_BASIC_ID ?? null;
  return {
    configured: lineConfigured(env) && Boolean(basicId),
    linked: Boolean(link),
    notifyMode: link?.notify_mode ?? null,
    notifyHour: link?.notify_hour ?? null,
    linkedAt: link?.linked_at ?? null,
    addFriendUrl: basicId ? addFriendUrl(basicId) : null,
  };
}

const UpdateDestinationInput = z
  .object({ events: z.array(z.enum(EVENT_NAMES)).min(1).max(2) })
  .strict();

export function destinationView(d: DestinationRow) {
  return {
    id: d.id,
    kind: d.kind,
    label: d.label,
    events: d.events,
    disabledReason: d.disabled_at ? (d.disabled_reason ?? "止まっています") : null,
    lastDeliveredAt: d.last_delivered_at,
    createdAt: d.created_at,
  };
}

const CreateTokenInput = z
  .object({
    name: z.string().trim().min(1).max(60),
    scopes: z.array(z.string()).max(5),
  })
  .strict();

const DecidePairingInput = z
  .object({
    decision: z.enum(["approve", "deny"]),
    scopes: z.array(z.string()).max(5).optional(),
  })
  .strict();

export function appRoutes() {
  const app = new Hono<AppEnv>();

  app.use("*", async (c, next) => {
    const userId = await verifyAppUser(c.env, c.req.raw);
    if (!userId) return c.json({ error: { code: "unauthorized", message: "サインインし直して" } }, 401);
    c.set("userId", userId);
    c.set("repo", new Repo(new Postgrest({ url: c.env.SUPABASE_URL, serviceKey: c.env.SUPABASE_SERVICE_ROLE_KEY })));
    await next();
  });

  // ---- 連携の一覧（アプリの「連携」画面） ----
  app.get("/connections", async (c) => {
    const userId = c.get("userId");
    const oauth = authorizationServer(c.env).getOAuthApi(c.env);
    const [tokens, grants, destinations, lineLink] = await Promise.all([
      c.get("repo").listApiTokens(userId),
      oauth.listUserGrants(userId),
      c.get("repo").listDestinations(userId),
      c.get("repo").lineLinkByUser(userId),
    ]);
    return c.json({
      mcpUrl: resourceUrls(c.env.PUBLIC_ORIGIN).mcp,
      apiBaseUrl: `${c.env.PUBLIC_ORIGIN}/v1`,
      docsUrl: `${c.env.SITE_ORIGIN}/connect/`,
      aiClients: grants.items.map((g) => ({
        id: g.id,
        name: (g.metadata as { clientName?: string } | null)?.clientName ?? g.clientId,
        domain: (g.metadata as { clientDomain?: string | null } | null)?.clientDomain ?? null,
        scopes: describeScopes(g.scope.filter((s) => s !== "offline_access")),
        createdAt: new Date(g.createdAt * 1000).toISOString(),
      })),
      line: lineView(c.env, lineLink),
      destinations: destinations.map(destinationView),
      providers: { slack: providerConfigured(c.env, "slack"), discord: providerConfigured(c.env, "discord") },
      apiTokens: tokens.map((t) => ({
        id: t.id,
        name: t.name,
        prefix: t.token_prefix,
        scopes: describeScopes(t.scopes),
        createdAt: t.created_at,
        lastUsedAt: t.last_used_at,
      })),
    });
  });

  // ---- API キー（PAT） ----
  app.post("/tokens", async (c) => {
    const parsed = CreateTokenInput.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: "invalid_request", message: "名前と権限を確かめて" } }, 400);
    const userId = c.get("userId");
    const repo = c.get("repo");
    if ((await repo.listApiTokens(userId)).length >= MAX_TOKENS_PER_USER) {
      return c.json({ error: { code: "too_many_tokens", message: `API キーは ${MAX_TOKENS_PER_USER} 個まで。使っていないものを消して` } }, 409);
    }
    const scopes = normalizeScopes(parsed.data.scopes);
    const pat = await generatePat();
    const row = await repo.createApiToken(userId, { name: parsed.data.name, hash: pat.hash, prefix: pat.prefix, scopes });
    // トークンそのものを返すのはこの 1 回だけ。
    return c.json({ id: row.id, name: row.name, token: pat.token, scopes: describeScopes(scopes), createdAt: row.created_at }, 201);
  });

  app.delete("/tokens/:id", async (c) => {
    const ok = await c.get("repo").revokeApiToken(c.get("userId"), c.req.param("id"));
    return ok ? c.body(null, 204) : c.json({ error: { code: "not_found", message: "その API キーは無い" } }, 404);
  });

  // ---- LINE ----

  // 連携コードを作り、LINE のトークを「連携 123456」が入った状態で開く URL を返す。
  app.post("/line/link-code", async (c) => {
    if (!lineConfigured(c.env) || !c.env.LINE_BASIC_ID) return c.json({ error: { code: "not_configured", message: "準備中です" } }, 503);
    const { code, expiresAt } = await c.get("repo").createLinkCode(c.get("userId"));
    return c.json({ code, expiresAt, openUrl: linkMessageUrl(c.env.LINE_BASIC_ID, code), addFriendUrl: addFriendUrl(c.env.LINE_BASIC_ID) }, 201);
  });

  app.patch("/line", async (c) => {
    const parsed = UpdateLineInput.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: "invalid_request", message: "通知の設定を確かめて" } }, 400);
    const row = await c.get("repo").updateLineSettings(c.get("userId"), parsed.data);
    return row ? c.json({ line: lineView(c.env, row) }) : c.json({ error: { code: "not_linked", message: "LINE と連携していません" } }, 404);
  });

  app.delete("/line", async (c) => {
    await c.get("repo").unlinkLine(c.get("userId"));
    return c.body(null, 204);
  });

  // ---- 送り先（Slack / Discord / 汎用 Webhook） ----

  // URL を貼って足す（上級者向け。Slack / Discord の URL なら、その形で送る）。
  app.post("/destinations", async (c) => {
    const parsed = CreateDestinationInput.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: "invalid_request", message: "URL を確かめて" } }, 400);
    const checked = checkDestinationUrl(parsed.data.url);
    if (!checked.ok) return c.json({ error: { code: "invalid_url", message: checked.reason } }, 422);
    const userId = c.get("userId");
    const repo = c.get("repo");
    if ((await repo.listDestinations(userId)).length >= MAX_DESTINATIONS_PER_USER) {
      return c.json({ error: { code: "too_many_destinations", message: `送り先は ${MAX_DESTINATIONS_PER_USER} 個まで` } }, 409);
    }
    // 汎用 Webhook には署名の鍵を付ける（受け取る側が、Gymnee から来たと確かめられるように）。
    const secret = checked.kind === "webhook" ? generateWebhookSecret() : null;
    const hello = await sendHello(c.env, checked.kind, checked.url, secret, (await repo.profile(userId))?.displayName ?? "Gymnee のユーザー", userId);
    if (!hello.ok) {
      return c.json({ error: { code: "unreachable", message: `送り先に届きませんでした（${hello.status ?? "通信できない"}）。URL を確かめて` } }, 422);
    }
    const row = await repo.createDestination(userId, {
      kind: checked.kind,
      label: parsed.data.label ?? checked.label,
      targetCiphertext: await encryptString(c.env.ENCRYPTION_KEY, checked.url),
      signingSecretCiphertext: secret ? await encryptString(c.env.ENCRYPTION_KEY, secret) : null,
      events: parsed.data.events ?? [...EVENT_NAMES],
    });
    // 署名の鍵を見せるのはこの 1 回だけ。
    return c.json({ destination: destinationView(row), signingSecret: secret }, 201);
  });

  app.patch("/destinations/:id", async (c) => {
    const parsed = UpdateDestinationInput.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: "invalid_request", message: "送る内容を 1 つ以上選んで" } }, 400);
    const row = await c.get("repo").updateDestinationEvents(c.get("userId"), c.req.param("id"), parsed.data.events);
    return row ? c.json({ destination: destinationView(row) }) : c.json({ error: { code: "not_found", message: "その送り先は無い" } }, 404);
  });

  // 止まった送り先を戻す（つながりを確かめる 1 通が届いたら戻す）。
  app.post("/destinations/:id/resume", async (c) => {
    const repo = c.get("repo");
    const userId = c.get("userId");
    const dest = await repo.destinationWithSecrets(userId, c.req.param("id"));
    if (!dest) return c.json({ error: { code: "not_found", message: "その送り先は無い" } }, 404);
    const target = await decryptString(c.env.ENCRYPTION_KEY, dest.target_ciphertext);
    const secret = dest.signing_secret_ciphertext ? await decryptString(c.env.ENCRYPTION_KEY, dest.signing_secret_ciphertext) : null;
    const hello = await sendHello(c.env, dest.kind, target, secret, (await repo.profile(userId))?.displayName ?? "Gymnee のユーザー", userId);
    if (!hello.ok) return c.json({ error: { code: "unreachable", message: "まだ届きません。送り先を消して、足し直してください" } }, 422);
    const row = await repo.resumeDestination(userId, dest.id);
    return c.json({ destination: row ? destinationView(row) : null });
  });

  app.delete("/destinations/:id", async (c) => {
    await c.get("repo").deleteDestination(c.get("userId"), c.req.param("id"));
    return c.body(null, 204);
  });

  // 「Slack に追加」「Discord に追加」: 認可の URL を返す（アプリが ASWebAuthenticationSession で開く）。
  app.get("/:provider{slack|discord}/start", async (c) => {
    const provider = c.req.param("provider") as ChatProvider;
    if (!providerConfigured(c.env, provider)) {
      return c.json({ error: { code: "not_configured", message: "準備中です" } }, 503);
    }
    if ((await c.get("repo").listDestinations(c.get("userId"))).length >= MAX_DESTINATIONS_PER_USER) {
      return c.json({ error: { code: "too_many_destinations", message: `送り先は ${MAX_DESTINATIONS_PER_USER} 個まで` } }, 409);
    }
    return c.json({ url: await authorizeUrl(c.env, provider, c.get("userId")), callbackScheme: "gymnee" });
  });

  // ---- AI の接続（OAuth の許可） ----
  app.delete("/grants/:id", async (c) => {
    const oauth = authorizationServer(c.env).getOAuthApi(c.env);
    // revokeGrant は持ち主の id でも絞るので、他人の許可は消せない。
    await oauth.revokeGrant(c.req.param("id"), c.get("userId"));
    return c.body(null, 204);
  });

  app.get("/oauth/pairings/:id", async (c) => {
    const p = await c.get("repo").pairing(c.req.param("id")).catch(() => null);
    if (!p || p.status !== "pending") {
      return c.json({ error: { code: "expired", message: "この承認は時間切れか、もう決まっている。接続をやり直して" } }, 410);
    }
    return c.json({
      id: p.id,
      code: p.code,
      clientName: p.client_name,
      clientDomain: p.client_domain,
      redirectHost: p.redirect_host,
      redirectIsLoopback: p.redirect_is_loopback,
      scopes: describeScopes(p.scopes),
      expiresAt: p.expires_at,
    });
  });

  app.post("/oauth/pairings/:id", async (c) => {
    const parsed = DecidePairingInput.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: { code: "invalid_request", message: "承認か拒否かを送って" } }, 400);
    const repo = c.get("repo");
    const pairing = await repo.pairing(c.req.param("id")).catch(() => null);
    if (!pairing || pairing.status !== "pending") {
      return c.json({ error: { code: "expired", message: "この承認は時間切れか、もう決まっている" } }, 410);
    }
    // 利用者が外した権限は渡さない。求められていない権限は足さない。
    const requested = new Set(pairing.scopes);
    const scopes = normalizeScopes((parsed.data.scopes ?? pairing.scopes).filter((s) => requested.has(s)));
    const ok = await repo.decidePairing(
      c.get("userId"),
      pairing.id,
      parsed.data.decision === "approve" ? "approved" : "denied",
      scopes,
    );
    if (!ok) return c.json({ error: { code: "expired", message: "この承認は時間切れか、もう決まっている" } }, 410);
    return c.json({ status: parsed.data.decision === "approve" ? "approved" : "denied", scopes: describeScopes(scopes) });
  });

  return app;
}
