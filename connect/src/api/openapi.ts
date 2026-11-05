// OpenAPI 3.1 の文書を operations.ts から作る。ドキュメント（gymnee.app/connect/api/）と
// https://api.gymnee.app/openapi.json は、どちらもこれを出したもの。手で書いた仕様書は持たない。

import { z } from "zod";
import { SCOPES } from "../domain/scopes.js";
import { operations, type Operation } from "./operations.js";

function schemaOf(type: z.ZodType): Record<string, unknown> {
  const s = z.toJSONSchema(type, { target: "openapi-3.0", unrepresentable: "any", io: "input" }) as Record<string, unknown>;
  delete s.$schema;
  return s;
}

function parameters(op: Operation) {
  const shape = op.input.shape as Record<string, z.ZodType>;
  const pathNames = [...op.path.matchAll(/\{(\w+)\}/g)].map((m) => m[1]!);
  const params: Record<string, unknown>[] = [];
  for (const name of pathNames) {
    params.push({ name, in: "path", required: true, schema: schemaOf(shape[name]!) });
  }
  if (op.method === "GET") {
    for (const [name, type] of Object.entries(shape)) {
      if (pathNames.includes(name)) continue;
      const schema = schemaOf(type);
      params.push({
        name,
        in: "query",
        required: !type.safeParse(undefined).success,
        description: (schema.description as string | undefined) ?? undefined,
        schema,
      });
    }
  }
  if (op.id === "log_workout") {
    params.push({
      name: "Idempotency-Key",
      in: "header",
      required: false,
      description: "再送で二重にならないための鍵（8〜100 文字）。同じ鍵の 2 回目は何も増やさず 200 を返す",
      schema: { type: "string", minLength: 8, maxLength: 100 },
    });
  }
  return params;
}

function requestBody(op: Operation) {
  if (op.method !== "POST") return undefined;
  const pathNames = [...op.path.matchAll(/\{(\w+)\}/g)].map((m) => m[1]!);
  const shape = { ...(op.input.shape as Record<string, z.ZodType>) };
  for (const name of pathNames) delete shape[name];
  // MCP 用の引数は REST の本文には出さない（REST はヘッダーで渡す）。
  delete shape.idempotencyKey;
  return { required: true, content: { "application/json": { schema: schemaOf(z.object(shape)) } } };
}

const errorSchema = {
  type: "object",
  properties: {
    error: {
      type: "object",
      properties: { code: { type: "string" }, message: { type: "string" }, details: {} },
      required: ["code", "message"],
    },
  },
};

export function openApiDocument(serverUrl: string) {
  const paths: Record<string, Record<string, unknown>> = {};
  for (const op of operations) {
    const success = op.method === "POST" ? "201" : "200";
    const responses: Record<string, unknown> = {
      [success]: {
        description: "成功",
        content: { "application/json": { schema: { type: "object", properties: { data: schemaOf(op.output) }, required: ["data"] } } },
      },
      "401": { description: "トークンが無い・切れている" },
      "403": { description: `権限が足りない（${op.scope} が要る）` },
      "429": { description: "呼び出しが多すぎる。少し待ってから" },
      "500": { description: "サーバー側の失敗", content: { "application/json": { schema: errorSchema } } },
    };
    if (op.method === "POST") responses["400"] = { description: "入力の形が違う", content: { "application/json": { schema: errorSchema } } };
    if (op.id === "log_workout") {
      responses["200"] = { description: "同じ Idempotency-Key で記録済み（何も増やしていない）" };
      responses["422"] = { description: "種目が決まらない・値が足りない（details に候補）", content: { "application/json": { schema: errorSchema } } };
    }
    if (op.path.includes("{")) responses["404"] = { description: "見つからない", content: { "application/json": { schema: errorSchema } } };
    paths[op.path] = {
      ...(paths[op.path] ?? {}),
      [op.method.toLowerCase()]: {
        operationId: op.id,
        summary: op.title,
        description: op.description,
        tags: [op.readOnly ? "読む" : "書く"],
        security: [{ oauth2: [op.scope] }, { bearer: [] }],
        parameters: parameters(op),
        requestBody: requestBody(op),
        responses,
        "x-required-scope": op.scope,
        "x-mcp-tool": op.id,
      },
    };
  }

  return {
    openapi: "3.1.0",
    info: {
      title: "Gymnee API",
      version: "1.0.0",
      description:
        "Gymnee の記録を読み書きする API。トークンはアプリの「その他 > 連携 > API キー」で作る（PAT）か、OAuth 2.1 で取る。" +
        "日時は ISO 8601、重量は kg、週は JST の月曜始まり。消す・直すはアプリだけで行う。",
    },
    servers: [{ url: serverUrl }],
    tags: [
      { name: "読む", description: "記録・自己ベスト・体重・パーティを読む（read）" },
      { name: "書く", description: "記録を足す（workouts:write）・メニューを提案する（coach:write）" },
    ],
    components: {
      securitySchemes: {
        bearer: { type: "http", scheme: "bearer", description: "PAT（gym_pat_…）。アプリで作る" },
        oauth2: {
          type: "oauth2",
          description: "MCP クライアント向け。承認は iPhone の Gymnee で行う",
          flows: {
            authorizationCode: {
              authorizationUrl: `${serverUrl}/authorize`,
              tokenUrl: `${serverUrl}/oauth/token`,
              refreshUrl: `${serverUrl}/oauth/token`,
              scopes: SCOPES,
            },
          },
        },
      },
    },
    paths,
  };
}
