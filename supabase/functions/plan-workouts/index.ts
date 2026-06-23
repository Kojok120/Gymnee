// AI ワークアウト計画（Premium, ⑧-8c）。Gemini にカレンダー予定＋ルーティン＋過去記録を渡し、
// 今週の各日のメニューを「種目＋セット＋目標重量/レップ」まで組ませる。
// GEMINI_API_KEY が未設定なら 503（クライアントは「準備中」表示）。
//
// デプロイ: supabase functions deploy plan-workouts
// キー設定: supabase secrets set GEMINI_API_KEY=xxxx
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// モデルは GEMINI_MODEL シークレットで切替可能（既定 gemini-2.5-flash）。
// 例: supabase secrets set GEMINI_MODEL=gemini-3.5-flash（アクセス可能なキーになったら）。
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "not_configured" }), { status: 503, headers: cors });
  }

  let body: any = {};
  try { body = await req.json(); } catch { /* empty */ }

  const days: string[] = Array.isArray(body.days) ? body.days : [];
  const routines: string[] = Array.isArray(body.routines) ? body.routines : [];
  const goal: number = Number(body.weeklyGoal ?? 3);
  const busy: any[] = Array.isArray(body.events) ? body.events : [];
  const history: any[] = Array.isArray(body.history) ? body.history : [];

  const prompt = [
    "あなたは熟練のパーソナルトレーナーです。以下の条件で今週のワークアウト計画を、種目・セット数・目標重量(kg)・レップまで具体的に組んでください。",
    `対象日(ISO yyyy-MM-dd, 日本時間): ${JSON.stringify(days)}`,
    `利用可能なルーティン名: ${JSON.stringify(routines.length ? routines : ["全身", "上半身", "下半身"])}`,
    `今週の目標トレーニング日数: ${goal}`,
    `既存の予定(避けるべき多忙日の参考): ${JSON.stringify(busy)}`,
    `直近4週間の記録(頻度・部位バランス・前回重量の参考。空なら初心者想定で控えめに): ${JSON.stringify(history)}`,
    "方針: 予定で忙しい日は休養または軽め。連続して同じ部位を高頻度で組まない。目標日数に合わせる。",
    "重量は過去記録の前回値を基準に漸進的過負荷(無理のない範囲で微増)。記録が無い種目は控えめな初期値。",
    'JSONのみを返す。形式: {"plan":[{"date":"<対象日>","title":"<部位/ルーティン名 or 休養>","exercises":[{"name":"種目名","muscleGroup":"chest|back|legs|shoulders|arms|core|fullBody のいずれか","sets":3,"reps":8,"weight":60}]}]}。休養日は exercises を空配列に。',
  ].join("\n");

  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { responseMimeType: "application/json", temperature: 0.7 },
        }),
      },
    );
    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{"plan":[]}';
    return new Response(text, { headers: cors });
  } catch (e) {
    return new Response(JSON.stringify({ error: "upstream", detail: String(e) }), { status: 502, headers: cors });
  }
});
