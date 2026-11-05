// gymnee-connect（api.gymnee.app）の入口。道の振り分けだけをここに置く。
//
//   /.well-known/*, /oauth/token, /oauth/register  OAuth の認可サーバー（ライブラリ）
//   /authorize                                     承認画面（iPhone の Gymnee で承認）
//   /mcp                                           MCP（OAuth か PAT）
//   /v1/*                                          REST API（OAuth か PAT）
//   /openapi.json                                  API の仕様（認証なし）
//   /app/*                                         iOS アプリ向け（アプリのサインイン）

import { Hono } from "hono";
import type { Env } from "./env.js";
import { Postgrest } from "./db/postgrest.js";
import { Repo } from "./db/repo.js";
import { GymneeService } from "./service.js";
import type { OAuthResourceContext, OAuthResourceHandler } from "@cloudflare/workers-oauth-provider";
import { authorizationServer, protectedResource, type AuthProps } from "./auth/oauth.js";
import { finishAuthorize, pairingStatus, showAuthorize } from "./auth/consent.js";
import { CORS_HEADERS, errorBody, handleRest, json } from "./api/rest.js";
import { openApiDocument } from "./api/openapi.js";
import { handleMcp } from "./mcp/server.js";
import { appRoutes } from "./app/routes.js";

function repoFor(env: Env): Repo {
  return new Repo(new Postgrest({ url: env.SUPABASE_URL, serviceKey: env.SUPABASE_SERVICE_ROLE_KEY }));
}

function withCors(res: Response): Response {
  const out = new Response(res.body, res);
  for (const [k, v] of Object.entries(CORS_HEADERS)) out.headers.set(k, v);
  return out;
}

/** 利用者ごとの呼び出しの上限。束縛が無い環境（ローカル）では制限しない。 */
async function rateLimited(env: Env, userId: string): Promise<boolean> {
  if (!env.API_RATE_LIMITER) return false;
  const { success } = await env.API_RATE_LIMITER.limit({ key: userId });
  return !success;
}

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.redirect(`${c.env.SITE_ORIGIN}/connect/`, 302));
app.get("/openapi.json", (c) => withCors(c.json(openApiDocument(c.env.PUBLIC_ORIGIN))));

// ---- OAuth（承認画面は自前、それ以外はライブラリ） ----
app.get("/authorize", (c) => showAuthorize(c.req.raw, c.env, repoFor(c.env)));
app.post("/authorize", (c) => finishAuthorize(c.req.raw, c.env, repoFor(c.env)));
app.get("/authorize/pairing/:id", (c) => pairingStatus(c.req.param("id"), repoFor(c.env)));

// ---- MCP と REST（トークンの確かめはリソースサーバーが行う） ----
const mcpHandler: OAuthResourceHandler<Env, AuthProps> = {
  async fetch(request: Request, env: Env, ctx: OAuthResourceContext<AuthProps>) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
    const { userId, scopes } = ctx.props;
    if (await rateLimited(env, userId)) return json(errorBody("rate_limited", "呼び出しが多すぎる。少し待って"), 429, { "Retry-After": "30" });
    return withCors(await handleMcp(request, { userId, scopes, service: new GymneeService(repoFor(env)) }));
  },
};

const restHandler: OAuthResourceHandler<Env, AuthProps> = {
  async fetch(request: Request, env: Env, ctx: OAuthResourceContext<AuthProps>) {
    const { userId, scopes } = ctx.props;
    if (await rateLimited(env, userId)) return json(errorBody("rate_limited", "呼び出しが多すぎる。少し待って"), 429, { "Retry-After": "30" });
    return handleRest(request, ctx.auth, { userId, scopes, service: new GymneeService(repoFor(env)) });
  },
};

app.on(["GET", "POST", "DELETE", "OPTIONS"], ["/mcp", "/mcp/*", "/.well-known/oauth-protected-resource/mcp"], async (c) => {
  if (c.req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  return withCors(await protectedResource(c.env, "mcp", mcpHandler).fetch(c.req.raw, c.env, c.executionCtx as ExecutionContext));
});

app.on(["GET", "POST", "OPTIONS"], ["/v1", "/v1/*", "/.well-known/oauth-protected-resource/v1"], async (c) => {
  if (c.req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  return withCors(await protectedResource(c.env, "v1", restHandler).fetch(c.req.raw, c.env, c.executionCtx as ExecutionContext));
});

// ---- アプリ向け ----
app.route("/app", appRoutes());

// ---- 残りは認可サーバー（メタデータ・トークン・登録・取り消し） ----
app.all("*", (c) => authorizationServer(c.env).fetch(c.req.raw, c.env, c.executionCtx as ExecutionContext));

export default {
  fetch: app.fetch,
} satisfies ExportedHandler<Env>;
