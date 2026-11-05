// PAT（個人用アクセストークン）。アプリで作り、作った直後に 1 回だけ見せる。DB にはハッシュだけを置く。

import { randomToken, sha256Hex } from "../domain/crypto.js";

export const PAT_PREFIX = "gym_pat_";

export interface NewPat {
  /** 利用者に渡す値（この 1 回しか見せない）。 */
  token: string;
  hash: string;
  /** 一覧で見分けるための先頭。これだけではトークンにならない。 */
  prefix: string;
}

export async function generatePat(): Promise<NewPat> {
  const token = `${PAT_PREFIX}${randomToken(32)}`;
  return { token, hash: await hashPat(token), prefix: token.slice(0, PAT_PREFIX.length + 4) };
}

export function hashPat(token: string): Promise<string> {
  return sha256Hex(token);
}
