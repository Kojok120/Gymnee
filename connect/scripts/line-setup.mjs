// LINE の公式アカウントの初期設定（本番への反映。岡本さんの明示 OK のあとに流す）。
//   node scripts/line-setup.mjs            # 何をするかだけ表示する（変更しない）
//   node scripts/line-setup.mjs --apply    # 実際に設定する
//
// やること:
//   1. Webhook の URL を https://api.gymnee.app/line/webhook にし、LINE から届くかを確かめる
//   2. リッチメニュー（assets/richmenu.png・4 つのボタン）を作り、全員の既定にする。前の Gymnee のメニューは消す
// 秘密は ../secrets/connect.env の LINE_MESSAGING_CHANNEL_ID / LINE_MESSAGING_CHANNEL_SECRET から読む。
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const apply = process.argv.includes("--apply");
const env = Object.fromEntries(
  readFileSync(join(here, "../../secrets/connect.env"), "utf8")
    .split("\n")
    .filter((l) => l.includes("=") && !l.trim().startsWith("#"))
    .map((l) => [l.slice(0, l.indexOf("=")).trim(), l.slice(l.indexOf("=") + 1).trim()]),
);
const WEBHOOK = process.env.WEBHOOK_URL ?? "https://api.gymnee.app/line/webhook";
const MENU_NAME = "gymnee-main";

if (!env.LINE_MESSAGING_CHANNEL_ID || !env.LINE_MESSAGING_CHANNEL_SECRET) {
  console.error("secrets/connect.env に LINE_MESSAGING_CHANNEL_ID と LINE_MESSAGING_CHANNEL_SECRET を書いてから流す");
  process.exit(1);
}

const tokenRes = await fetch("https://api.line.me/oauth2/v3/token", {
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({ grant_type: "client_credentials", client_id: env.LINE_MESSAGING_CHANNEL_ID, client_secret: env.LINE_MESSAGING_CHANNEL_SECRET }),
});
if (!tokenRes.ok) {
  console.error("トークンを取れない", tokenRes.status, await tokenRes.text());
  process.exit(1);
}
const { access_token: token } = await tokenRes.json();
const api = (path, init = {}) =>
  fetch(`${path.startsWith("https://") ? "" : "https://api.line.me"}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, ...(init.body && !(init.body instanceof Uint8Array) ? { "Content-Type": "application/json" } : {}), ...(init.headers ?? {}) },
  });

const info = await api("/v2/bot/info").then((r) => r.json());
console.log("公式アカウント:", info.displayName, info.basicId);
const current = await api("/v2/bot/channel/webhook/endpoint").then((r) => r.json());
console.log("いまの Webhook:", current.endpoint ?? "(未設定)", current.active ? "有効" : "無効");
const menus = (await api("/v2/bot/richmenu/list").then((r) => r.json())).richmenus ?? [];
const ours = menus.filter((m) => m.name === MENU_NAME);
console.log("いまのリッチメニュー:", menus.map((m) => `${m.name}(${m.richMenuId})`).join(", ") || "(なし)");

if (!apply) {
  console.log(`\n--apply を付けると: Webhook を ${WEBHOOK} にし、リッチメニュー ${MENU_NAME} を作り直して既定にする（前の ${ours.length} 個は消す）`);
  process.exit(0);
}

// 1. Webhook
const put = await api("/v2/bot/channel/webhook/endpoint", { method: "PUT", body: JSON.stringify({ endpoint: WEBHOOK }) });
console.log("Webhook の設定:", put.status);
const test = await api("/v2/bot/channel/webhook/test", { method: "POST", body: JSON.stringify({ endpoint: WEBHOOK }) }).then((r) => r.json());
console.log("Webhook の確かめ:", test.success ? "OK" : `NG ${test.statusCode} ${test.reason ?? ""}`);

// 2. リッチメニュー（ボタンの並びは make-richmenu-image.py と同じ）
const W = 2500;
const H = 843;
const col = W / 4;
const actions = [
  { type: "postback", data: "rm:menu", displayText: "今日のメニュー", label: "今日のメニュー" },
  { type: "postback", data: "rm:log", displayText: "記録する", label: "記録する" },
  { type: "postback", data: "rm:review", displayText: "今週のふりかえり", label: "ふりかえり" },
  { type: "postback", data: "rm:consult", displayText: "相談する", label: "相談する" },
];
const created = await api("/v2/bot/richmenu", {
  method: "POST",
  body: JSON.stringify({
    size: { width: W, height: H },
    selected: true,
    name: MENU_NAME,
    chatBarText: "メニュー",
    areas: actions.map((action, i) => ({ bounds: { x: Math.round(i * col), y: 0, width: Math.round(col), height: H }, action })),
  }),
}).then((r) => r.json());
if (!created.richMenuId) {
  console.error("リッチメニューを作れない", created);
  process.exit(1);
}
const image = readFileSync(join(here, "../assets/richmenu.png"));
const upload = await api(`https://api-data.line.me/v2/bot/richmenu/${created.richMenuId}/content`, {
  method: "POST",
  headers: { "Content-Type": "image/png" },
  body: new Uint8Array(image),
});
console.log("画像の登録:", upload.status);
const setDefault = await api(`/v2/bot/user/all/richmenu/${created.richMenuId}`, { method: "POST" });
console.log("既定にする:", setDefault.status);
for (const m of ours) {
  const del = await api(`/v2/bot/richmenu/${m.richMenuId}`, { method: "DELETE" });
  console.log("前のメニューを消す:", m.richMenuId, del.status);
}
console.log("完了");
