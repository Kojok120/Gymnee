// OAuth 2.1 の認可サーバー（MCP の接続に使う）と、リソース（/mcp・/v1）でのトークンの確かめ方。
// トークンは 2 種類を受ける:
//   - OAuth のアクセストークン（Claude・ChatGPT などが「URL を追加」したときに取りに来る）
//   - PAT（gym_pat_…。アプリで作り、スクリプトや Claude Code に貼る）
// どちらも中身は「利用者 id と権限（スコープ）」だけ。Supabase の JWT は外に出さない。

import { OAuthAuthorizationServer, OAuthResourceServer, type OAuthResourceHandler } from "@cloudflare/workers-oauth-provider";
import type { Env } from "../env.js";
import { Postgrest } from "../db/postgrest.js";
import { Repo } from "../db/repo.js";
import { ALL_SCOPES, BASE_SCOPE } from "../domain/scopes.js";
import { PAT_PREFIX, hashPat } from "./pat.js";

export interface AuthProps {
  userId: string;
  /** 許された権限。OAuth はトークンのスコープ、PAT は作ったときに選んだもの。 */
  scopes: string[];
  via: "oauth" | "pat";
}

const ACCESS_TOKEN_TTL = 60 * 60; // 1 時間
const REFRESH_TOKEN_IDLE_TTL = 60 * 60 * 24 * 90; // 使われない日が 90 日続いたら切れる
const REFRESH_TOKEN_TTL = 60 * 60 * 24 * 365; // 使い続けても 1 年で切れる

const servers = new Map<string, OAuthAuthorizationServer<Env>>();

export function resourceUrls(origin: string) {
  return { mcp: `${origin}/mcp`, v1: `${origin}/v1` };
}

/** 認可サーバー。issuer は Worker の公開 URL（ローカルでは http://localhost:8787）。 */
export function authorizationServer(env: Env): OAuthAuthorizationServer<Env> {
  const origin = env.PUBLIC_ORIGIN;
  let server = servers.get(origin);
  if (!server) {
    const resources = resourceUrls(origin);
    server = new OAuthAuthorizationServer<Env>({
      issuer: origin,
      resources: [resources.mcp, resources.v1],
      defaultResource: resources.mcp,
      scopesSupported: [...ALL_SCOPES, "offline_access"],
      clientRegistrationEndpoint: "/oauth/register",
      clientIdMetadataDocumentEnabled: true,
      accessTokenTTL: ACCESS_TOKEN_TTL,
      refreshTokenIdleTTL: REFRESH_TOKEN_IDLE_TTL,
      refreshTokenTTL: REFRESH_TOKEN_TTL,
    });
    servers.set(origin, server);
  }
  return server;
}

/** PAT の確かめ。持ち主と権限を DB から引く。どのリソースにも使える。 */
async function validatePat(env: Env, token: string, resource: string) {
  const repo = new Repo(new Postgrest({ url: env.SUPABASE_URL, serviceKey: env.SUPABASE_SERVICE_ROLE_KEY }));
  const row = await repo.apiTokenByHash(await hashPat(token));
  if (!row) return null;
  // 使った日時は一覧に出すだけなので、失敗しても認証は通す。
  repo.touchApiToken(row.id).catch(() => undefined);
  const props: AuthProps = { userId: row.user_id, scopes: row.scopes, via: "pat" };
  return { props, audience: resource, scope: row.scopes, userId: row.user_id, clientId: `pat:${row.id}` };
}

function resourceServer(
  env: Env,
  resource: string,
  handler: OAuthResourceHandler<Env, AuthProps>,
): OAuthResourceServer<Env, AuthProps> {
  return new OAuthResourceServer<Env, AuthProps>({
    resourceMetadata: {
      resource,
      authorization_servers: [env.PUBLIC_ORIGIN],
      resource_name: "Gymnee",
    },
    requiredScopes: [BASE_SCOPE],
    validateToken: (e) => async (res, token) => {
      if (token.startsWith(PAT_PREFIX)) return validatePat(e, token, res);
      const validated = await authorizationServer(e).validateToken<AuthProps>(res, token, e);
      if (!validated) return null;
      // スコープはトークンに載っているものを正とする（props は承認したときの控え）。
      const props: AuthProps = { userId: validated.userId, scopes: validated.scope, via: "oauth" };
      return { ...validated, props };
    },
    handler,
  });
}

const resourceServers = new Map<string, OAuthResourceServer<Env, AuthProps>>();

/** /mcp と /v1 のリソースサーバー（Worker の公開 URL ごとに 1 つずつ作って使い回す）。 */
export function protectedResource(
  env: Env,
  kind: "mcp" | "v1",
  handler: OAuthResourceHandler<Env, AuthProps>,
): OAuthResourceServer<Env, AuthProps> {
  const key = `${env.PUBLIC_ORIGIN}|${kind}`;
  let server = resourceServers.get(key);
  if (!server) {
    server = resourceServer(env, resourceUrls(env.PUBLIC_ORIGIN)[kind], handler);
    resourceServers.set(key, server);
  }
  return server;
}
