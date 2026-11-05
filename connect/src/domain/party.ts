// 週ボスの名前。アプリの PartyBoss.catalog とサーバーの party_boss_id の並びの写し。
// ボスを足したら 3 か所（Swift・SQL・ここ）を同時に直す。季節のボスはアプリ側の読み替えだけなのでここには無い。

export const BOSS_NAMES: Record<string, string> = {
  sloth_slime: "サボリスライム",
  couch_golem: "ソファゴーレム",
  snooze_dragon: "ネボウドラゴン",
  junk_kraken: "ジャンククラーケン",
};

export function bossName(id: string): string {
  return BOSS_NAMES[id] ?? "週のボス";
}
