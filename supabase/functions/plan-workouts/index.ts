// AI ワークアウト計画（Premium, ⑧-8c）。Gemini にカレンダー予定＋ルーティン＋過去記録を渡し、
// 今週の各日のメニューを「種目＋セット＋目標重量/レップ」まで組ませる。
// GEMINI_API_KEY が未設定なら 503（クライアントは「準備中」表示）。
//
// デプロイ: supabase functions deploy plan-workouts
// キー設定: supabase secrets set GEMINI_API_KEY=xxxx
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// モデル/APIバージョンは secrets で切替可能。既定は gemini-3.1-flash-lite(v1beta)。
// （直接検証で当該モデル＋現行キーが v1beta/v1 とも 200 を返すことを確認済み）
// 例: supabase secrets set GEMINI_MODEL=gemini-3.1-flash-lite GEMINI_API_VERSION=v1beta
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.1-flash-lite";
const API_VERSION = Deno.env.get("GEMINI_API_VERSION") ?? "v1beta";

/// 応答テキストから JSON 本体（最初の { 〜 最後の }）を取り出す。コードフェンスや前置きを除去。
function extractJson(s: string): string {
  const a = s.indexOf("{");
  const b = s.lastIndexOf("}");
  return a >= 0 && b > a ? s.slice(a, b + 1) : s;
}

/// 認証 JWT(sub=ユーザーid)を取り出す（レート制限キー用。検証は verify_jwt が担う）。
function userIdFromJWT(req: Request): string | null {
  try {
    const auth = req.headers.get("authorization") ?? "";
    const token = auth.replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(atob(token.split(".")[1]));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

/// ユーザー別の直近呼び出し時刻（ベストエフォートのレート制限。インスタンス内のみ）。
const lastCall = new Map<string, number>();

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

  // 認証必須（Gemini コスト乱用の抑止）。アプリ同梱の公開 publishable key だけでの匿名実行を拒否する。
  // ゲートウェイの verify_jwt(=署名検証) とは別に、関数側でも user JWT(sub) の存在を必須化する多層防御。
  // クライアントは isBackendAuthenticated 時のみ Authorization: Bearer(user JWT) を付けて呼ぶため正規経路は無影響。
  const sub = userIdFromJWT(req);
  if (!sub) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers: cors });
  }

  // 簡易レート制限（認証ユーザー単位・ベストエフォート＝インスタンス内）。
  {
    const now = Date.now();
    if (lastCall.size > 5000) lastCall.clear();
    const prev = lastCall.get(sub);
    if (prev && now - prev < 8000) {
      return new Response(JSON.stringify({ error: "rate_limited" }), { status: 429, headers: cors });
    }
    lastCall.set(sub, now);
  }

  let body: any = {};
  try { body = await req.json(); } catch { /* empty */ }

  // 入力上限（プロンプト膨張＝コスト膨張を防ぐ）。超過分は切り詰める。
  const days: string[] = (Array.isArray(body.days) ? body.days : []).slice(0, 14);
  const routines: string[] = (Array.isArray(body.routines) ? body.routines : [])
    .slice(0, 30).map((r: any) => String(r).slice(0, 40));
  const goal: number = Math.max(0, Math.min(14, Number(body.weeklyGoal ?? 3) || 0));
  const busy: any[] = (Array.isArray(body.events) ? body.events : []).slice(0, 100);
  const history: any[] = (Array.isArray(body.history) ? body.history : []).slice(0, 200);
  // 部位ごとの回復状況（recovered=false の部位は避ける根拠）。
  const recovery: any[] = (Array.isArray(body.recovery) ? body.recovery : []).slice(0, 12);

  const prompt = [
    "あなたは熟練のパーソナルトレーナーです。以下の条件で今週のワークアウト計画を、種目・セット数・目標重量(kg)・レップまで具体的に組んでください。",
    `対象日(ISO yyyy-MM-dd, 日本時間): ${JSON.stringify(days)}`,
    `利用可能なルーティン名: ${JSON.stringify(routines.length ? routines : ["全身", "上半身", "下半身"])}`,
    `今週の目標トレーニング日数: ${goal}`,
    `既存の予定(避けるべき多忙日の参考): ${JSON.stringify(busy)}`,
    `直近4週間の記録(頻度・部位バランス・前回重量の参考。空なら初心者想定で控えめに): ${JSON.stringify(history)}`,
    `部位ごとの回復状況(recovered=false=未回復。hoursSince=最終トレからの経過時間): ${JSON.stringify(recovery)}`,
    "方針: 予定で忙しい日は休養または軽め。目標日数に合わせる。各トレ日の部位は『部位ごとの回復状況』で決める＝ hoursSince が長い(最も休めている)/recovered=true の部位を優先し、recovered=false の部位は連日に入れない。",
    "【最重要・分割の原則】週全体で主要部位(胸・背中・脚・肩・腕)をバランスよく分割する。1つの部位やルーティンに偏らせない。同じ部位は週に最大2回、連続するトレ日は必ず異なる部位にする(例: 胸→背中→脚→肩/腕)。同じ内容の繰り返しは禁止。",
    "利用可能なルーティンが無い/少ない/1つだけの場合は、それを毎日繰り返さず、各トレ日を【オリジナルに】個別種目を組み合わせて構成する。回復状況で最も休めている部位から順に割り当て、title はその部位名にし、その部位の主要種目を2〜4種目入れる。ルーティンを使える日は1ルーティンにつき週1回まで割り当ててよい。",
    "重量は過去記録の前回値を基準に漸進的過負荷(無理のない範囲で微増)。記録が無い種目は控えめな初期値。",
    'JSONのみを返す。形式: {"plan":[{"date":"<対象日>","title":"<部位/ルーティン名 or 休養>","exercises":[{"name":"種目名","muscleGroup":"chest|back|legs|shoulders|arms|core|fullBody のいずれか","sets":3,"reps":8,"weight":60}]}]}。休養日は exercises を空配列に。',
  ].join("\n");

  // Gemini 呼び出し。ハング対策に 25s で打ち切り（AbortSignal）、一過性の失敗
  // （タイムアウト/429/5xx）は 1 回だけ短い待ちで再試行する。2 回失敗なら 502。
  // 最悪 25s+1s+25s ≈ 51s で、クライアント（functions 用 session 60s）より先に必ず返る。
  const callGemini = () =>
    fetch(
      `https://generativelanguage.googleapis.com/${API_VERSION}/models/${MODEL}:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          // v1 は responseMimeType 非対応のため、プロンプトでJSON指定＋本文から抽出する。
          generationConfig: { temperature: 0.7 },
        }),
        signal: AbortSignal.timeout(25_000),
      },
    );

  try {
    let res: Response;
    try {
      res = await callGemini();
      if (res.status === 429 || res.status >= 500) throw new Error(`gemini_status_${res.status}`);
    } catch (_first) {
      await new Promise((r) => setTimeout(r, 1_000));
      res = await callGemini();
    }
    if (!res.ok) {
      return new Response(JSON.stringify({ error: "upstream", detail: `gemini_status_${res.status}` }), { status: 502, headers: cors });
    }
    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{"plan":[]}';
    return new Response(extractJson(text), { headers: cors });
  } catch (e) {
    return new Response(JSON.stringify({ error: "upstream", detail: String(e) }), { status: 502, headers: cors });
  }
});
