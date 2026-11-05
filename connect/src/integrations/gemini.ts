// Gemini の呼び出し（JSON で返させる）。キーと既定のモデルは Edge Function の coach-chat と同じものを使う。
// 出力は壊れることがあるので、JSON 本体の取り出しと、生の JSON を利用者に見せない歯止めをここに置く。

import type { Env } from "../env.js";

const DEFAULT_MODEL = "gemini-3.5-flash-lite";

export interface GeminiTurn {
  role: "user" | "model";
  text: string;
}

export function geminiConfigured(env: Env): boolean {
  return Boolean(env.GEMINI_API_KEY);
}

/** 応答テキストから JSON 本体（最初の { 〜 最後の }）を取り出す。 */
export function extractJson(s: string): string {
  const a = s.indexOf("{");
  const b = s.lastIndexOf("}");
  return a >= 0 && b > a ? s.slice(a, b + 1) : s;
}

/** JSON の断片が返答に紛れ込んでいないか（壊れた出力をそのまま見せない）。 */
export function looksLikeJson(text: string): boolean {
  const t = text.trim();
  return t.startsWith("{") || t.startsWith("[") || t.includes('"reply"') || t.includes('"intent"');
}

export async function generateJson(
  env: Env,
  turns: GeminiTurn[],
  options: { temperature?: number; maxOutputTokens?: number } = {},
  doFetch: typeof fetch = (i, init) => fetch(i, init),
): Promise<unknown | null> {
  if (!env.GEMINI_API_KEY) return null;
  const model = env.GEMINI_MODEL || DEFAULT_MODEL;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const res = await doFetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
    body: JSON.stringify({
      contents: turns.map((t) => ({ role: t.role, parts: [{ text: t.text }] })),
      generationConfig: {
        temperature: options.temperature ?? 0.6,
        maxOutputTokens: options.maxOutputTokens ?? 1500,
        responseMimeType: "application/json",
      },
    }),
    signal: AbortSignal.timeout(25_000),
  });
  if (!res.ok) {
    console.error("gemini error", res.status, (await res.text()).slice(0, 300));
    return null;
  }
  const json = (await res.json()) as { candidates?: { content?: { parts?: { text?: string }[] }; finishReason?: string }[] };
  const raw = json.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  const finish = json.candidates?.[0]?.finishReason;
  if (finish && finish !== "STOP") console.error("gemini finishReason", finish);
  try {
    return JSON.parse(extractJson(raw));
  } catch {
    return null;
  }
}
