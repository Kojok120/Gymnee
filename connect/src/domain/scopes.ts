// 外部に渡すトークンの権限。アプリのログイン（Supabase の JWT）より必ず狭くする。
// 第三者の AI やスクリプトに、投稿・削除・他人のデータに触れる力は渡さない（#171）。

export const SCOPES = {
  read: "記録・自己ベスト・体重（アプリで記録した分）・パーティの状況を読む",
  "workouts:write": "ワークアウトの記録を足す（消す・直すはできない）",
  "coach:write": "アプリのコーチ画面にメニューを提案する",
} as const;

export type Scope = keyof typeof SCOPES;

export const ALL_SCOPES = Object.keys(SCOPES) as Scope[];

/** どの操作にも要る権限。MCP のクライアントは最初にこれを求める。 */
export const BASE_SCOPE: Scope = "read";

export function isScope(value: string): value is Scope {
  return Object.prototype.hasOwnProperty.call(SCOPES, value);
}

/**
 * 求められた権限を、知っているものだけに絞る。read はどの操作にも要るので必ず含める。
 * 並びは SCOPES の順にそろえる（表示と比較を安定させる）。
 */
export function normalizeScopes(requested: readonly string[]): Scope[] {
  const wanted = new Set<string>([BASE_SCOPE, ...requested]);
  return ALL_SCOPES.filter((s) => wanted.has(s));
}

export function hasScopes(granted: readonly string[], needed: readonly Scope[]): boolean {
  return needed.every((s) => granted.includes(s));
}

/** 画面に出す日本語の説明。 */
export function describeScopes(scopes: readonly string[]): { scope: Scope; label: string }[] {
  return normalizeScopes(scopes).map((scope) => ({ scope, label: SCOPES[scope] }));
}
