// 外部（LINE の文・AI の道具呼び出し）から来た種目名を、Gymnee の種目に合わせる。
// 知らない名前で新しい種目を勝手に作らない（種目が増殖し、記録が別種目に散るため）。
// 一つに決まらなければ候補を返し、利用者か AI に選び直してもらう。

import type { ExerciseInfo } from "./types.js";

/** 表記ゆれを畳む: 全角半角・大小・空白・中黒・ひらがな/カタカナ。 */
export function normalizeName(raw: string): string {
  return raw
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s・･\-_/()（）]/g, "")
    .replace(/[ぁ-ゖ]/g, (c) => String.fromCharCode(c.charCodeAt(0) + 0x60));
}

function bigrams(s: string): string[] {
  if (s.length < 2) return [s];
  const out: string[] = [];
  for (let i = 0; i < s.length - 1; i++) out.push(s.slice(i, i + 2));
  return out;
}

/** 文字の 2 文字組の重なり（Dice 係数、0〜1）。 */
export function similarity(a: string, b: string): number {
  const x = bigrams(a);
  const y = bigrams(b);
  const pool = new Map<string, number>();
  for (const g of y) pool.set(g, (pool.get(g) ?? 0) + 1);
  let hit = 0;
  for (const g of x) {
    const n = pool.get(g) ?? 0;
    if (n > 0) {
      hit += 1;
      pool.set(g, n - 1);
    }
  }
  return (2 * hit) / (x.length + y.length);
}

export type MatchResult =
  | { kind: "matched"; exercise: ExerciseInfo }
  | { kind: "ambiguous"; candidates: ExerciseInfo[] }
  | { kind: "unknown"; candidates: ExerciseInfo[] };

/**
 * 名前から種目を引く。
 * 1. 正規化して完全一致（自分の種目を優先）
 * 2. 片方がもう片方を含み、候補が 1 つだけ（「ベンチ」→「ベンチプレス」）
 * 3. それ以外は似ている順に最大 3 件を候補として返す
 */
export function matchExercise(name: string, catalog: readonly ExerciseInfo[]): MatchResult {
  const key = normalizeName(name);
  if (!key) return { kind: "unknown", candidates: [] };
  const normalized = catalog.map((e) => ({ e, n: normalizeName(e.name) }));

  const exact = normalized.filter((x) => x.n === key).map((x) => x.e);
  if (exact.length > 0) {
    const own = exact.find((e) => e.isCustom);
    return { kind: "matched", exercise: own ?? exact[0]! };
  }

  const containing = normalized.filter((x) => x.n.includes(key) || key.includes(x.n)).map((x) => x.e);
  if (containing.length === 1) return { kind: "matched", exercise: containing[0]! };

  const ranked = normalized
    .map((x) => ({ e: x.e, score: similarity(key, x.n) + (containing.includes(x.e) ? 0.5 : 0) }))
    .filter((x) => x.score > 0.2)
    .sort((a, b) => b.score - a.score || a.e.name.localeCompare(b.e.name))
    .slice(0, 3)
    .map((x) => x.e);
  return containing.length > 1 ? { kind: "ambiguous", candidates: ranked } : { kind: "unknown", candidates: ranked };
}
