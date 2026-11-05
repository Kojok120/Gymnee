// Worker の環境変数と束縛。秘密は `wrangler secret put` で入れる（値は secrets/connect.env と Supabase から）。

export interface Env {
  /** OAuth の許可・トークン・承認待ちの組（ペアリング）を置く KV。 */
  OAUTH_KV: KVNamespace;
  /** 利用者ごとの呼び出し回数の上限（Workers Rate Limiting）。無ければ制限しない。 */
  API_RATE_LIMITER?: RateLimit;

  /** この Worker の公開 URL（https://api.gymnee.app）。OAuth の issuer にもなる。 */
  PUBLIC_ORIGIN: string;
  /** Web サイト（https://gymnee.app）。ユニバーサルリンクとドキュメントの置き場所。 */
  SITE_ORIGIN: string;

  SUPABASE_URL: string;
  /** アプリのトークンを確かめるときの apikey（publishable / anon。秘密ではない）。 */
  SUPABASE_PUBLISHABLE_KEY: string;
  /** service role（secret key）。repo.ts からしか使わない。 */
  SUPABASE_SERVICE_ROLE_KEY: string;

  /** 送り先 URL などを暗号化する鍵（32 バイトの base64）。 */
  ENCRYPTION_KEY: string;
  /** state・ペアリングの署名に使う秘密（32 文字以上）。 */
  STATE_SECRET: string;

  GEMINI_API_KEY?: string;
  GEMINI_MODEL?: string;

  LINE_MESSAGING_CHANNEL_ID?: string;
  LINE_MESSAGING_CHANNEL_SECRET?: string;
  LINE_LOGIN_CHANNEL_ID?: string;
  LINE_LOGIN_CHANNEL_SECRET?: string;
  LINE_BASIC_ID?: string;

  SLACK_CLIENT_ID?: string;
  SLACK_CLIENT_SECRET?: string;
  DISCORD_CLIENT_ID?: string;
  DISCORD_CLIENT_SECRET?: string;

  /** 運営への知らせ（LINE の通数の残りが少ない等）を送る Discord の Webhook。無ければ送らない。 */
  OPS_ALERT_WEBHOOK_URL?: string;
}
