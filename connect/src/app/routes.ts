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

type AppEnv = { Bindings: Env; Variables: { userId: string; repo: Repo } };

/** 1 人が持てる API キーの数（作りっぱなしを防ぐ）。 */
const MAX_TOKENS_PER_USER = 10;

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
    const [tokens, grants] = await Promise.all([c.get("repo").listApiTokens(userId), oauth.listUserGrants(userId)]);
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
