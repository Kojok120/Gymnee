// 送り先の URL を見分けて確かめる（純粋）。貼り付けた URL も OAuth で受け取った URL もここを通す。
// 内部の宛先へ送らせない（SSRF）。Workers の global_fetch_strictly_public でも塞いでいるが、入口でも断る。

export type DestinationKind = "slack" | "discord" | "webhook";

export type UrlCheck =
  | { ok: true; kind: DestinationKind; url: string; label: string }
  | { ok: false; reason: string };

const SLACK = /^https:\/\/hooks\.slack\.com\/services\/[A-Z0-9]+\/[A-Z0-9]+\/[A-Za-z0-9]+$/;
const DISCORD = /^https:\/\/(?:(?:canary|ptb)\.)?(?:discord|discordapp)\.com\/api\/(?:v\d+\/)?webhooks\/\d+\/[\w-]+$/;

function isIpLiteral(host: string): boolean {
  return /^\d{1,3}(?:\.\d{1,3}){3}$/.test(host) || host.startsWith("[") || host.includes(":");
}

function isInternalName(host: string): boolean {
  return (
    host === "localhost" ||
    host.endsWith(".localhost") ||
    host.endsWith(".local") ||
    host.endsWith(".internal") ||
    host.endsWith(".lan") ||
    host.endsWith(".home.arpa") ||
    !host.includes(".")
  );
}

export function checkDestinationUrl(raw: string): UrlCheck {
  const text = raw.trim();
  if (text.length === 0 || text.length > 2048) return { ok: false, reason: "URL の長さが合わない" };
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return { ok: false, reason: "URL の形ではない" };
  }
  if (url.protocol !== "https:") return { ok: false, reason: "https の URL にして" };
  if (url.username || url.password) return { ok: false, reason: "URL にユーザー名やパスワードを入れない" };
  if (url.port && url.port !== "443") return { ok: false, reason: "443 以外のポートには送れない" };
  const host = url.hostname.toLowerCase();
  if (isIpLiteral(host) || isInternalName(host)) return { ok: false, reason: "公開されているドメインの URL にして" };

  const normalized = `${url.origin}${url.pathname}${url.search}`;
  if (host === "hooks.slack.com") {
    if (!SLACK.test(`${url.origin}${url.pathname}`) || url.search) return { ok: false, reason: "Slack の Incoming Webhook の URL（hooks.slack.com/services/…）にして" };
    return { ok: true, kind: "slack", url: normalized, label: "Slack" };
  }
  if (/(^|\.)discord(app)?\.com$/.test(host)) {
    if (!DISCORD.test(`${url.origin}${url.pathname}`)) return { ok: false, reason: "Discord の Webhook の URL（discord.com/api/webhooks/…）にして" };
    return { ok: true, kind: "discord", url: `${url.origin}${url.pathname}`, label: "Discord" };
  }
  return { ok: true, kind: "webhook", url: normalized, label: host };
}
