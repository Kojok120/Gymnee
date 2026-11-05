// REST API（/v1）。operations.ts の定義をそのまま HTTP に載せる。
// 認証（トークンの確かめ）はリソースサーバーが済ませ、ここには利用者 id と権限が届く。

import { insufficientScope, type OAuthResourceAuth } from "@cloudflare/workers-oauth-provider";
import { z } from "zod";
import { PostgrestError } from "../db/postgrest.js";
import { hasScopes } from "../domain/scopes.js";
import type { GymneeService } from "../service.js";
import { OperationError, operations, type Operation } from "./operations.js";

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, Idempotency-Key, Mcp-Session-Id, Mcp-Protocol-Version",
  "Access-Control-Expose-Headers": "WWW-Authenticate, Mcp-Session-Id",
};

export function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...CORS_HEADERS, ...extra },
  });
}

export function errorBody(code: string, message: string, details?: unknown) {
  return { error: { code, message, ...(details === undefined ? {} : { details }) } };
}

/** OpenAPI のパス（/v1/workouts/{workoutId}）を、実際のパスと照らし合わせる。 */
function matchPath(template: string, path: string): Record<string, string> | null {
  const t = template.split("/").filter(Boolean);
  const p = path.replace(/\/$/, "").split("/").filter(Boolean);
  if (t.length !== p.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < t.length; i++) {
    const seg = t[i]!;
    if (seg.startsWith("{") && seg.endsWith("}")) params[seg.slice(1, -1)] = decodeURIComponent(p[i]!);
    else if (seg !== p[i]) return null;
  }
  return params;
}

export function routeOperation(method: string, path: string): { op: Operation; params: Record<string, string> } | null {
  for (const op of operations) {
    if (op.method !== method) continue;
    const params = matchPath(op.path, path);
    if (params) return { op, params };
  }
  return null;
}

/** 失敗をそのまま HTTP の答えに変える（中身の漏れない形で）。 */
export function failure(error: unknown): Response {
  if (error instanceof OperationError) return json(errorBody(error.code, error.message, error.details), error.status);
  if (error instanceof z.ZodError) return json(errorBody("invalid_request", "入力の形が違う", z.treeifyError(error)), 400);
  if (error instanceof PostgrestError && error.status === 400) return json(errorBody("invalid_request", "入力の形が違う"), 400);
  console.error("api error", error instanceof Error ? error.message : String(error));
  return json(errorBody("server_error", "うまく処理できなかった。時間をおいてもう一度試して"), 500);
}

export async function handleRest(
  request: Request,
  auth: OAuthResourceAuth,
  ctx: { userId: string; scopes: string[]; service: GymneeService },
): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  const url = new URL(request.url);
  const route = routeOperation(request.method, url.pathname);
  if (!route) return json(errorBody("not_found", "その API は無い。一覧は /openapi.json"), 404);
  const { op, params } = route;

  if (!hasScopes(ctx.scopes, [op.scope])) {
    const res = insufficientScope(auth, [op.scope], `この操作には ${op.scope} の権限が要る`);
    for (const [k, v] of Object.entries(CORS_HEADERS)) res.headers.set(k, v);
    return res;
  }

  let raw: Record<string, unknown> = { ...params };
  if (op.method === "GET") {
    for (const [k, v] of url.searchParams) raw[k] = v;
  } else {
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return json(errorBody("invalid_request", "本文は JSON で送る"), 400);
    }
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      return json(errorBody("invalid_request", "本文は JSON のオブジェクトで送る"), 400);
    }
    raw = { ...(body as Record<string, unknown>), ...params };
  }

  try {
    const input = op.input.parse(raw);
    const idempotencyKey = request.headers.get("Idempotency-Key") ?? undefined;
    if (idempotencyKey !== undefined && (idempotencyKey.length < 8 || idempotencyKey.length > 100)) {
      return json(errorBody("invalid_request", "Idempotency-Key は 8〜100 文字"), 400);
    }
    const data = await op.run({ userId: ctx.userId, service: ctx.service, idempotencyKey, channel: "api" }, input);
    const status = op.method === "POST" && (data as { created?: boolean })?.created !== false ? 201 : 200;
    return json({ data }, status);
  } catch (error) {
    return failure(error);
  }
}
