// AI ワークアウト計画（Premium, ⑧-8c）。Gemini にカレンダー予定＋ルーティンを渡し、
// 今週の各日に何をやるかを提案させる。GEMINI_API_KEY が未設定なら 503（クライアントは「準備中」表示）。
//
// デプロイ: supabase functions deploy plan-workouts
// キー設定: supabase secrets set GEMINI_API_KEY=xxxx
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const MODEL = "gemini-2.0-flash";

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

  const prompt = [
    "あなたは熟練のパーソナルトレーナーです。以下の条件で今週のワークアウト計画を立ててください。",
    `対象日(ISO8601, 日本時間想定): ${JSON.stringify(days)}`,
    `利用可能なルーティン名: ${JSON.stringify(routines.length ? routines : ["全身", "上半身", "下半身"])}`,
    `今週の目標トレーニング日数: ${goal}`,
    `既存の予定(避けるべき多忙日の参考): ${JSON.stringify(busy)}`,
    "制約: 予定で忙しい日は休養または軽め。連続して同じ部位を高頻度で行わない。目標日数に合わせる。",
    'JSONのみを返す。形式: {"plan":[{"date":"<対象日のいずれか>","title":"<ルーティン名 or 休養>"}]}。',
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
