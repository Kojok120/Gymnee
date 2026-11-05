// 日付の計算は JST で行う。週は月曜始まり（サーバーの party_week_start と同じ）。
// Workers の実行環境は UTC なので、Date を JST の暦に読み替える小さな関数だけを置く。

const JST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** JST の暦日（YYYY-MM-DD）。 */
export function jstDay(date: Date): string {
  return new Date(date.getTime() + JST_OFFSET_MS).toISOString().slice(0, 10);
}

/** JST の時（0〜23）。 */
export function jstHour(date: Date): number {
  return new Date(date.getTime() + JST_OFFSET_MS).getUTCHours();
}

/** JST の暦日の 0 時を指す Date。 */
export function jstStartOfDay(date: Date): Date {
  const shifted = new Date(date.getTime() + JST_OFFSET_MS);
  shifted.setUTCHours(0, 0, 0, 0);
  return new Date(shifted.getTime() - JST_OFFSET_MS);
}

/** JST の月曜 0 時（その日を含む週の始まり）。 */
export function jstWeekStart(date: Date): Date {
  const start = jstStartOfDay(date);
  const weekday = new Date(start.getTime() + JST_OFFSET_MS).getUTCDay(); // 0=日
  const back = (weekday + 6) % 7; // 月曜からの日数
  return new Date(start.getTime() - back * DAY_MS);
}

/** JST の暦日で何日違うか（a から b まで。b が後なら正）。 */
export function jstDaysBetween(a: Date, b: Date): number {
  return Math.round((jstStartOfDay(b).getTime() - jstStartOfDay(a).getTime()) / DAY_MS);
}

export function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * DAY_MS);
}

/** JST の「M月D日」。 */
export function jstMonthDay(date: Date): string {
  const d = new Date(date.getTime() + JST_OFFSET_MS);
  return `${d.getUTCMonth() + 1}月${d.getUTCDate()}日`;
}
