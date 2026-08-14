// AI コーチとの会話（#79）。ユーザーの発言＋直近の会話＋記録の要約を Gemini に渡し、
// 返答と（必要なら）その日のメニュー提案を返す。
//
// plan-workouts と分けている理由: あちらは「週の計画をまとめて組む」一括処理で、
// こちらは「1 往復の会話」。プロンプトも応答形式も寿命も別物のため、同居させると両方が壊れやすい。
//
// デプロイ: supabase functions deploy coach-chat
// キー設定: supabase secrets set GEMINI_API_KEY=xxxx （plan-workouts と同じキーを共用）
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.5-flash-lite";
const API_VERSION = Deno.env.get("GEMINI_API_VERSION") ?? "v1beta";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

/// 応答テキストから JSON 本体（最初の { 〜 最後の }）を取り出す。コードフェンスや前置きを除去。
function extractJson(s: string): string {
  const a = s.indexOf("{");
  const b = s.lastIndexOf("}");
  return a >= 0 && b > a ? s.slice(a, b + 1) : s;
}

/// 壊れた JSON から reply の中身だけを拾う。
/// 出力が途中で切れると `{"reply": "胸と背中の…` のように閉じ引用符すら無いので、
/// 「reply の値の開始位置から、閉じ引用符 or 文字列の終わりまで」を素朴に取り出す。
function salvageReply(raw: string): string {
  const key = raw.indexOf('"reply"');
  if (key < 0) return "";
  const start = raw.indexOf('"', raw.indexOf(":", key) + 1);
  if (start < 0) return "";
  let out = "";
  for (let i = start + 1; i < raw.length; i++) {
    const c = raw[i];
    if (c === "\\") { i++; out += raw[i] === "n" ? "\n" : (raw[i] ?? ""); continue; }
    if (c === '"') break;
    out += c;
  }
  return out.trim().slice(0, 500);
}

/// JSON の断片が返答として紛れ込んでいないか。
function looksLikeJSON(text: string): boolean {
  const t = text.trim();
  return t.startsWith("{") || t.startsWith("[") || t.includes('"reply"') || t.includes('"plan"');
}

/// 認証 JWT(sub=ユーザーid)を取り出す（レート制限キー用。署名検証は verify_jwt が担う）。
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

/// コーチの人格と禁止事項。クライアント側の CoachPersona と対で管理する。
const PERSONA = `
あなたは筋トレアプリ Gymnee のコーチです。ユーザーの記録だけを根拠に、短く具体的に話します。

人格:
- 実務的で穏やか。淡々としているが冷たくない
- 1〜3文で答える。前置きや相槌だけの返事はしない
- 敬語は使わず、親しい指導者の口調（「〜しよう」「〜してみて」）
- 絵文字は使わない

必ず守ること:
- サボりや空白期間を責めない。休むことを肯定し、軽い内容から戻す提案をする
- 痛み・不調を訴えられたら、その部位を避けたメニューに組み替える。診断や医療的な断定はせず、
  強い痛みが続く場合は医療機関を勧める
- **ユーザーの記録について**、渡された内容に無い事実を作らない。記録の話で分からないことは
  「記録が足りない」と言う。ただしアプリの仕組みは下に書いてあるので、それは答える
- 数値（重量・レップ）は直近の記録から地続きの範囲で提案する。急に大きく上げない
- アプリ内の報酬や強さを約束しない。強くなるのは現実のトレーニングだけ

このアプリの仕組み（全ユーザー共通の仕様。聞かれたら答えてよい）:
- テストステロンパワー: 記録すると貯まる（1回につき 20 + セット数×2、1回の上限は60）。
  使い道は遠征の燃料。床に落ちた物を拾っても少し増える
- 遠征: パワーを払ってキャラをドアから送り出すと、時間が経っておみやげ（装備）を持ち帰る。
  レベルが上がると行ける場所が増える
- EXP とレベル: 記録するほど増える（行った事実 + セット数 + 総量 + 自己ベスト）
- 進化段階: レベル・自己ベストの数・連続週の3つを満たすと進化して、姿が変わる
- 部位別ステータス: 鍛えた部位の総量がそのまま体型に出る
- 見た目とペット: 買えるが、強さにも遠征の結果にも影響しない
- 手に入るのは装備と見た目とパワーだけ。強くなるのは現実のトレーニングだけ

仕組みを聞かれたら、渡された growth（いまのパワー・レベル・段階・次の段階に足りないもの）を
使って具体的に答える。値が渡っていなければ仕組みだけ説明する。
`;

/// 返答の形。plan は「今日のメニューを組み替える／新しく出す」ときだけ入れさせる。
const RESPONSE_SHAPE = `
出力は次の JSON だけを返してください（前後に説明文を付けない）。

{
  "reply": "ユーザーへの返答（1〜3文）",
  "plan": {
    "title": "メニュー名（例: 胸と三頭）",
    "exercises": [
      { "name": "種目名", "sets": 3, "reps": 10, "weightKg": 60 }
    ]
  }
}

plan はメニューを提案・変更するときだけ含めてください。雑談や質問への回答だけなら plan は省略します。
種目名は日本語。weightKg は自重種目なら 0 にしてください。
`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "not_configured" }), { status: 503, headers: cors });
  }

  // 認証必須（Gemini コスト乱用の抑止）。plan-workouts と同じ多層防御。
  const sub = userIdFromJWT(req);
  if (!sub) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers: cors });
  }

  // 簡易レート制限（認証ユーザー単位・ベストエフォート＝インスタンス内）。
  // 1 日あたりの上限はクライアント側（CoachQuota）が持ち、ここは連打だけを止める。
  {
    const now = Date.now();
    if (lastCall.size > 5000) lastCall.clear();
    const prev = lastCall.get(sub);
    if (prev && now - prev < 2000) {
      return new Response(JSON.stringify({ error: "rate_limited" }), { status: 429, headers: cors });
    }
    lastCall.set(sub, now);
  }

  let body: any = {};
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400, headers: cors });
  }

  const message: string = typeof body.message === "string" ? body.message.slice(0, 2000) : "";
  if (!message) {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400, headers: cors });
  }

  // 直近の会話（多すぎるとコストが跳ねるので後ろから 12 通だけ）。
  const history: Array<{ role: string; text: string }> = Array.isArray(body.messages)
    ? body.messages.slice(-12)
    : [];
  const brief = body.brief ?? {};
  // 「全部おまかせ」ならメニューを確定まで、「提案だけ」なら下書きに留めさせる。
  const decides = body.decidesMenu === true;

  const contents = [
    { role: "user", parts: [{ text: `${PERSONA}\n${RESPONSE_SHAPE}` }] },
    {
      role: "user",
      parts: [{
        text: `いまのユーザーの状況（記録の話はこの情報だけを根拠にしてください。` +
          `アプリの仕組みの説明は上の仕様に従ってください）:\n${JSON.stringify(brief)}\n` +
          (decides
            ? "モード: 全部おまかせ。メニューを聞かれたら、迷わせずに一つに決めて提示してください。"
            : "モード: 提案だけ。メニューは案として示し、変更を促す一言を添えてください。"),
      }],
    },
    ...history.map((m) => ({
      role: m.role === "coach" ? "model" : "user",
      parts: [{ text: String(m.text ?? "").slice(0, 2000) }],
    })),
    { role: "user", parts: [{ text: message }] },
  ];

  const url =
    `https://generativelanguage.googleapis.com/${API_VERSION}/models/${MODEL}:generateContent?key=${apiKey}`;

  let raw = "";
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents,
        // 1500 まで上げる。800 だとメニュー提案つきの応答が途中で切れ、
        // JSON が壊れて生テキストが表示される事故につながった。
        generationConfig: { temperature: 0.7, maxOutputTokens: 1500, responseMimeType: "application/json" },
      }),
    });
    if (!res.ok) {
      const detail = await res.text();
      console.error("gemini error", res.status, detail.slice(0, 500));
      return new Response(JSON.stringify({ error: "upstream" }), { status: 502, headers: cors });
    }
    const json = await res.json();
    raw = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    // 上限で打ち切られると JSON が壊れる。原因究明のために記録しておく。
    const finish = json?.candidates?.[0]?.finishReason;
    if (finish && finish !== "STOP") console.error("gemini finishReason", finish);
  } catch (e) {
    console.error("gemini fetch failed", e);
    return new Response(JSON.stringify({ error: "upstream" }), { status: 502, headers: cors });
  }

  // モデルの出力は壊れることがある。壊れていても会話は続けられるようにする。
  let reply = "";
  let plan: any = null;
  try {
    const parsed = JSON.parse(extractJson(raw));
    reply = typeof parsed.reply === "string" ? parsed.reply.trim() : "";
    if (parsed.plan && Array.isArray(parsed.plan.exercises) && parsed.plan.exercises.length > 0) {
      plan = {
        title: typeof parsed.plan.title === "string" ? parsed.plan.title : "今日のメニュー",
        exercises: parsed.plan.exercises.slice(0, 8).map((e: any) => ({
          name: String(e?.name ?? "").slice(0, 60),
          sets: Number.isFinite(e?.sets) ? Math.max(1, Math.min(10, Math.round(e.sets))) : 3,
          reps: Number.isFinite(e?.reps) ? Math.max(1, Math.min(50, Math.round(e.reps))) : 10,
          weightKg: Number.isFinite(e?.weightKg) ? Math.max(0, Math.min(500, Math.round(e.weightKg))) : 0,
        })).filter((e: any) => e.name.length > 0),
      };
      if (plan.exercises.length === 0) plan = null;
    }
  } catch {
    // JSON が壊れている（多くは出力が途中で切れたケース）。
    // **生の JSON を返答として出さない**。実際に `{ "reply": "…` がそのまま
    // ユーザーに表示される事故が起きた。まず reply の中身だけ拾い出す。
    reply = salvageReply(raw);
  }

  // 二重の歯止め: 何らかの経路で JSON らしき文字列が残っていたら捨てる。
  if (looksLikeJSON(reply)) reply = "";

  if (!reply) reply = "うまく言葉にできなかった。もう一度聞いてくれる？";

  return new Response(JSON.stringify({ reply, plan }), { headers: cors });
});
