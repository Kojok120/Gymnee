// 決定的な id（UUID v5）。同じ入力からは必ず同じ id になる。
// 外部からの記録の追加で「同じ依頼を 2 回送っても 1 件しか増えない」ようにするのに使う（冪等）。

/** 外部連携の名前空間（#171 用に新しく採番。アプリのプリセット種目の名前空間とは別）。 */
export const CONNECT_NAMESPACE = "6f0f4c1e-6b3d-4b5e-9f62-3a3c1d0e7b21";

function uuidToBytes(uuid: string): Uint8Array {
  const hex = uuid.replace(/-/g, "");
  const out = new Uint8Array(16);
  for (let i = 0; i < 16; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function bytesToUuid(bytes: Uint8Array): string {
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

/** RFC 4122 の UUID v5（SHA-1）。 */
export async function uuidV5(name: string, namespace: string = CONNECT_NAMESPACE): Promise<string> {
  const ns = uuidToBytes(namespace);
  const nameBytes = new TextEncoder().encode(name);
  const input = new Uint8Array(ns.length + nameBytes.length);
  input.set(ns);
  input.set(nameBytes, ns.length);
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-1", input)).slice(0, 16);
  hash[6] = (hash[6]! & 0x0f) | 0x50;
  hash[8] = (hash[8]! & 0x3f) | 0x80;
  return bytesToUuid(hash);
}

/**
 * 外部から足す記録の id。Idempotency-Key があれば（利用者 id とあわせて）決定的に作り、無ければ乱数。
 * 子の行（種目の行・セット）の id も同じ鍵から作るので、再送しても行は増えない。
 */
export async function workoutIds(
  userId: string,
  idempotencyKey: string | undefined,
  shape: number[],
): Promise<{ workoutId: string; exerciseIds: string[]; setIds: string[][] }> {
  const base = idempotencyKey ? `${userId}:${idempotencyKey}` : crypto.randomUUID();
  const workoutId = await uuidV5(`workout:${base}`);
  const exerciseIds: string[] = [];
  const setIds: string[][] = [];
  for (let i = 0; i < shape.length; i++) {
    exerciseIds.push(await uuidV5(`we:${base}:${i}`));
    const sets: string[] = [];
    for (let j = 0; j < shape[i]!; j++) sets.push(await uuidV5(`set:${base}:${i}:${j}`));
    setIds.push(sets);
  }
  return { workoutId, exerciseIds, setIds };
}
