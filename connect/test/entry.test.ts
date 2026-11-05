import { describe, expect, it } from "vitest";
import type { OAuthResourceAuth } from "@cloudflare/workers-oauth-provider";
import { handleRest, routeOperation } from "../src/api/rest.js";
import { openApiDocument } from "../src/api/openapi.js";
import { operations } from "../src/api/operations.js";
import { handleMcp } from "../src/mcp/server.js";
import { GymneeService } from "../src/service.js";
import type { Repo } from "../src/db/repo.js";
import type { ExerciseInfo } from "../src/domain/types.js";

const USER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const bench: ExerciseInfo = { id: "11111111-1111-4111-8111-111111111111", name: "ベンチプレス", muscleGroup: "chest", equipment: "barbell", measurementType: "weight", loadMode: "none", isCustom: false };

/** DB の代わり。呼ばれた利用者 id を記録し、ほかの利用者の値で呼ばれていないかを見る。 */
function fakeRepo() {
  const calls: { method: string; userId: string; payload?: unknown }[] = [];
  const logged = new Map<string, unknown>();
  const repo = {
    calls,
    async profile(userId: string) { calls.push({ method: "profile", userId }); return { id: userId, displayName: "テスト" }; },
    async weeklyGoal(userId: string) { calls.push({ method: "weeklyGoal", userId }); return 3; },
    async completedWorkouts(userId: string) { calls.push({ method: "completedWorkouts", userId }); return []; },
    async workout(userId: string) { calls.push({ method: "workout", userId }); return null; },
    async exercises(userId: string) { calls.push({ method: "exercises", userId }); return [bench]; },
    async setsForExercises(userId: string) {
      calls.push({ method: "setsForExercises", userId });
      return [{ exerciseId: bench.id, completedAt: "2026-11-01T10:00:00Z", workoutId: "w0", set: { set_index: 0, weight: 60, reps: 10, duration_seconds: null, distance_km: null, is_pr: false } }];
    },
    async personalRecords(userId: string) { calls.push({ method: "personalRecords", userId }); return []; },
    async bodyMetrics(userId: string) { calls.push({ method: "bodyMetrics", userId }); return []; },
    async partyOverview(userId: string) { calls.push({ method: "partyOverview", userId }); return []; },
    async logWorkout(userId: string, payload: Record<string, unknown>) {
      calls.push({ method: "logWorkout", userId, payload });
      const id = payload.id as string;
      const created = !logged.has(id);
      logged.set(id, payload);
      return { workout_id: id, created };
    },
    async addCoachMessage(userId: string, message: unknown) { calls.push({ method: "addCoachMessage", userId, payload: message }); return { id: "m1" }; },
  };
  return repo;
}

function service(repo: ReturnType<typeof fakeRepo>) {
  return new GymneeService(repo as unknown as Repo, () => new Date("2026-11-05T12:00:00+09:00"));
}

const auth = (scope: string[]): OAuthResourceAuth => ({ token: "t", audience: "http://localhost/v1", scope, userId: USER } as OAuthResourceAuth);

describe("operations / OpenAPI", () => {
  it("道具名・operationId は重複しない", () => {
    const ids = operations.map((o) => o.id);
    expect(new Set(ids).size).toBe(ids.length);
  });
  it("OpenAPI を作れて、すべての操作が載る", () => {
    const doc = openApiDocument("https://api.gymnee.app");
    const ops = Object.values(doc.paths).flatMap((p) => Object.values(p));
    expect(ops).toHaveLength(operations.length);
    expect(JSON.stringify(doc)).not.toContain("idempotencyKey\":{"); // REST の本文には MCP 用の引数を出さない
  });
  it("パスの照合", () => {
    expect(routeOperation("GET", "/v1/workouts/11111111-1111-4111-8111-111111111111")?.op.id).toBe("get_workout");
    expect(routeOperation("GET", "/v1/workouts")?.op.id).toBe("list_workouts");
    expect(routeOperation("POST", "/v1/workouts")?.op.id).toBe("log_workout");
    expect(routeOperation("DELETE", "/v1/workouts")).toBeNull();
  });
});

describe("REST", () => {
  it("summary を読む（認証した利用者の id だけで引く）", async () => {
    const repo = fakeRepo();
    const res = await handleRest(new Request("http://localhost/v1/summary"), auth(["read"]), { userId: USER, scopes: ["read"], service: service(repo) });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { data: { weeklyGoal: number } };
    expect(body.data.weeklyGoal).toBe(3);
    expect(repo.calls.every((c) => c.userId === USER)).toBe(true);
  });

  it("権限が足りなければ 403 insufficient_scope", async () => {
    const res = await handleRest(
      new Request("http://localhost/v1/workouts", { method: "POST", body: JSON.stringify({ exercises: [] }) }),
      auth(["read"]),
      { userId: USER, scopes: ["read"], service: service(fakeRepo()) },
    );
    expect(res.status).toBe(403);
    expect(res.headers.get("WWW-Authenticate")).toContain("insufficient_scope");
  });

  it("記録を足す: 自己ベストを判定し、Idempotency-Key の再送は増やさない", async () => {
    const repo = fakeRepo();
    const req = () =>
      new Request("http://localhost/v1/workouts", {
        method: "POST",
        headers: { "Idempotency-Key": "retry-key-001", "Content-Type": "application/json" },
        body: JSON.stringify({ name: "胸", exercises: [{ name: "ベンチプレス", sets: [{ weightKg: 65, reps: 5 }] }] }),
      });
    const ctx = { userId: USER, scopes: ["read", "workouts:write"], service: service(repo) };
    const first = await handleRest(req(), auth(ctx.scopes), ctx);
    expect(first.status).toBe(201);
    const firstBody = (await first.json()) as { data: { workoutId: string; personalRecords: { label: string }[] } };
    expect(firstBody.data.personalRecords.map((p) => p.label)).toContain("最大重量");
    const second = await handleRest(req(), auth(ctx.scopes), ctx);
    expect(second.status).toBe(200);
    const secondBody = (await second.json()) as { data: { workoutId: string; created: boolean } };
    expect(secondBody.data.workoutId).toBe(firstBody.data.workoutId);
    expect(secondBody.data.created).toBe(false);
    const payload = repo.calls.find((c) => c.method === "logWorkout")?.payload as { personal_records: { type: string }[] };
    // 65kg×5 の推定 1RM（75.8）は過去の 60kg×10（80）に届かないので、最大重量だけが自己ベスト。
    expect(payload.personal_records.map((p) => p.type)).toEqual(["max_weight"]);
  });

  it("本文の user_id などの余計な項目は受け付けない", async () => {
    const ctx = { userId: USER, scopes: ["read", "workouts:write"], service: service(fakeRepo()) };
    const res = await handleRest(
      new Request("http://localhost/v1/workouts", { method: "POST", body: JSON.stringify({ userId: "someone-else", exercises: [{ name: "ベンチプレス", sets: [{ weightKg: 60, reps: 5 }] }] }) }),
      auth(ctx.scopes),
      ctx,
    );
    expect(res.status).toBe(400);
  });

  it("種目が決まらなければ 422 と候補", async () => {
    const ctx = { userId: USER, scopes: ["read", "workouts:write"], service: service(fakeRepo()) };
    const res = await handleRest(
      new Request("http://localhost/v1/workouts", { method: "POST", body: JSON.stringify({ exercises: [{ name: "スクワット", sets: [{ weightKg: 60, reps: 5 }] }] }) }),
      auth(ctx.scopes),
      ctx,
    );
    expect(res.status).toBe(422);
  });
});

describe("MCP", () => {
  async function rpc(scopes: string[], body: unknown, repo = fakeRepo()) {
    const res = await handleMcp(
      new Request("http://localhost/mcp", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream", "Mcp-Protocol-Version": "2025-11-25" },
        body: JSON.stringify(body),
      }),
      { userId: USER, scopes, service: service(repo) },
    );
    return { status: res.status, body: (await res.json()) as { result?: Record<string, unknown>; error?: unknown } };
  }

  it("initialize に答え、説明（instructions）を渡す", async () => {
    const r = await rpc(["read"], {
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "test", version: "1" } },
    });
    expect(r.status).toBe(200);
    expect(String(r.body.result?.instructions)).toContain("get_summary");
  });

  it("権限で使える道具だけを見せる", async () => {
    const readOnly = await rpc(["read"], { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} });
    const names = (readOnly.body.result?.tools as { name: string }[]).map((t) => t.name);
    expect(names).toContain("get_summary");
    expect(names).not.toContain("log_workout");
    const all = await rpc(["read", "workouts:write", "coach:write"], { jsonrpc: "2.0", id: 3, method: "tools/list", params: {} });
    expect((all.body.result?.tools as { name: string }[]).map((t) => t.name)).toContain("log_workout");
  });

  it("道具を呼ぶ: 提案はコーチのメッセージとして本人に届く", async () => {
    const repo = fakeRepo();
    const r = await rpc(
      ["read", "coach:write"],
      { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "propose_menu", arguments: { title: "胸", message: "今日は胸にしよう", exercises: [{ name: "ベンチプレス", sets: 3, reps: 8, weightKg: 60 }] } } },
      repo,
    );
    expect(r.body.result?.isError).toBeUndefined();
    const call = repo.calls.find((c) => c.method === "addCoachMessage");
    expect(call?.userId).toBe(USER);
    expect(call?.payload).toMatchObject({ isFromCoach: true, proposal: { title: "胸", exercises: [{ name: "ベンチプレス", sets: 3, reps: 8, weightKg: 60 }] } });
  });

  it("権限の無い道具は、つなぎ直しの案内を返す", async () => {
    const r = await rpc(["read"], { jsonrpc: "2.0", id: 5, method: "tools/call", params: { name: "log_workout", arguments: {} } });
    expect(r.body.result?.isError).toBe(true);
  });

  it("prompts を出す", async () => {
    const list = await rpc(["read"], { jsonrpc: "2.0", id: 6, method: "prompts/list", params: {} });
    expect((list.body.result?.prompts as { name: string }[]).map((p) => p.name)).toEqual(["weekly_review", "plan_next_week", "plateau_check"]);
    const got = await rpc(["read"], { jsonrpc: "2.0", id: 7, method: "prompts/get", params: { name: "plateau_check", arguments: { exercise: "ベンチプレス" } } });
    expect(JSON.stringify(got.body.result)).toContain("ベンチプレス");
  });
});
