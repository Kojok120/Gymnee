// MCP サーバー（/mcp、Streamable HTTP・状態を持たない形）。
// 道具は operations.ts の定義から作る（REST と同じ中身・同じ検証）。
// 決まった問いかけ（prompts）を用意して、AI に詳しくない人でもボタン 1 つで使えるようにする。

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { CfWorkerJsonSchemaValidator } from "@modelcontextprotocol/sdk/validation/cfworker";
import {
  CallToolRequestSchema,
  GetPromptRequestSchema,
  ListPromptsRequestSchema,
  ListToolsRequestSchema,
  McpError,
  ErrorCode,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import { hasScopes } from "../domain/scopes.js";
import type { GymneeService } from "../service.js";
import { OperationError, operations } from "../api/operations.js";
import { PROMPTS, renderPrompt } from "./prompts.js";

export const SERVER_INSTRUCTIONS = `
Gymnee は筋トレの記録アプリ。この接続で、利用者本人の記録を読み、必要なら記録を足したり、アプリのコーチ画面にメニューを提案したりできる。

- まず get_summary で今の状況（今週の回数・目標・連続週・直近の記録）を読んでから話す。
- 重量は kg、日時は ISO 8601、週は日本時間の月曜始まり。
- 記録にない事実を作らない。分からないことは「記録が足りない」と言う。
- 重量・回数の提案は、直近の記録から地続きの範囲にする（get_exercise_history で確かめる）。急に大きく上げない。
- 痛みや不調を言われたら、その部位を避ける。診断や医療的な断定はしない。強い痛みが続くなら医療機関を勧める。
- サボりや空白期間を責めない。休むことを肯定し、軽い内容から戻す。
- 記録を足すとき（log_workout）は、足す内容を利用者に見せて確かめてから呼ぶ。種目名が一つに決まらないと候補が返るので、利用者に選んでもらって呼び直す。idempotencyKey を付けて二重登録を防ぐ。
- メニューは propose_menu でアプリのコーチ画面に届ける。アプリの計画を直接書き換えることはできない（取り込むかは利用者がアプリで決める）。
- 消す・直すはできない。必要ならアプリで行うよう案内する。
`.trim();

function toolResult(data: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
}

function toolError(message: string, details?: unknown) {
  const text = details === undefined ? message : `${message}\n${JSON.stringify(details, null, 2)}`;
  return { content: [{ type: "text" as const, text }], isError: true };
}

/** 1 回のリクエストごとにサーバーを作る（状態を持たないので、Worker のどのインスタンスでも同じに動く）。 */
export function buildMcpServer(ctx: { userId: string; scopes: string[]; service: GymneeService }): Server {
  const server = new Server(
    { name: "gymnee", title: "Gymnee", version: "1.0.0", websiteUrl: "https://gymnee.app/connect/" },
    {
      capabilities: { tools: {}, prompts: {} },
      instructions: SERVER_INSTRUCTIONS,
      jsonSchemaValidator: new CfWorkerJsonSchemaValidator(),
    },
  );

  // 許された権限で使える道具だけを見せる（使えない道具を AI に呼ばせて失敗させない）。
  const allowed = operations.filter((op) => hasScopes(ctx.scopes, [op.scope]));

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: allowed.map((op) => {
      const schema = z.toJSONSchema(op.input, { io: "input", unrepresentable: "any" }) as Record<string, unknown>;
      delete schema.$schema;
      return {
        name: op.id,
        title: op.title,
        description: op.description,
        inputSchema: { ...schema, type: "object" as const },
        annotations: {
          title: op.title,
          readOnlyHint: op.readOnly,
          destructiveHint: false,
          idempotentHint: op.idempotent,
          openWorldHint: false,
        },
      };
    }),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const op = allowed.find((o) => o.id === request.params.name);
    if (!op) {
      const exists = operations.some((o) => o.id === request.params.name);
      return toolError(
        exists
          ? "この接続には、その操作の権限がない。Gymnee アプリで接続を解除し、権限を付けてつなぎ直して。"
          : `その道具は無い: ${request.params.name}`,
      );
    }
    const parsed = op.input.safeParse(request.params.arguments ?? {});
    if (!parsed.success) return toolError("引数の形が違う", z.treeifyError(parsed.error));
    try {
      return toolResult(await op.run({ userId: ctx.userId, service: ctx.service }, parsed.data));
    } catch (error) {
      if (error instanceof OperationError) return toolError(error.message, error.details);
      console.error("mcp tool error", op.id, error instanceof Error ? error.message : String(error));
      return toolError("うまく処理できなかった。時間をおいてもう一度試して。");
    }
  });

  server.setRequestHandler(ListPromptsRequestSchema, async () => ({
    prompts: PROMPTS.map((p) => ({ name: p.name, title: p.title, description: p.description, arguments: p.arguments })),
  }));

  server.setRequestHandler(GetPromptRequestSchema, async (request) => {
    const rendered = renderPrompt(request.params.name, request.params.arguments ?? {});
    if (!rendered) throw new McpError(ErrorCode.InvalidParams, `その問いかけは無い: ${request.params.name}`);
    return rendered;
  });

  return server;
}

export async function handleMcp(
  request: Request,
  ctx: { userId: string; scopes: string[]; service: GymneeService },
): Promise<Response> {
  const server = buildMcpServer(ctx);
  const transport = new WebStandardStreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  await server.connect(transport);
  try {
    return await transport.handleRequest(request);
  } finally {
    // 状態を持たない形なので、1 回答えたら閉じる。
    void server.close();
  }
}
