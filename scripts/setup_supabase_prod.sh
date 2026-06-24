#!/usr/bin/env bash
#
# 本番 Supabase プロジェクトのセットアップ自動化（docs/production-setup.md ステップ3）。
# dev で実証済みの API 呼び出しをそのまま prod ref に対して流す。
#
# 前提:
#   - 引数に本番の Project Ref
#   - 環境変数 SUPABASE_ACCESS_TOKEN（ダッシュボードの PAT, sbp_...）。未設定なら macOS keychain の
#     `supabase login` トークンを使う（このマシン限定のフォールバック）。
#   - secrets/ に AuthKey_*.p8 / google_oauth.env / resend.env がある
#   - jq / openssl / supabase CLI
#
# 流すもの: スキーマ(setup_all.sql) → auth設定(Apple/Google/email/SMTP/redirect/OTP) →
#           Function deploy + secrets → push_config 投入
#
# ★手動の前後作業（このスクリプトでは出来ない）は docs/production-setup.md を参照。
set -euo pipefail

PROD_REF="${1:-}"
if [ -z "$PROD_REF" ]; then echo "usage: $0 <PROD_PROJECT_REF>"; exit 1; fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$ROOT/secrets"

# --- 依存チェック ---
for c in jq openssl supabase curl; do command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }; done
for f in "$SECRETS/google_oauth.env" "$SECRETS/resend.env"; do [ -s "$f" ] || { echo "missing secret file: $f"; exit 1; }; done
P8="$(ls "$SECRETS"/AuthKey_*.p8 2>/dev/null | head -1)"
[ -n "$P8" ] || { echo "missing APNs key: $SECRETS/AuthKey_*.p8"; exit 1; }

# --- access token ---
TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  raw="$(security find-generic-password -s 'Supabase CLI' -a supabase -w 2>/dev/null || true)"
  raw="${raw#go-keyring-encoded:}"; raw="${raw#go-keyring-base64:}"
  TOKEN="$(printf '%s' "$raw" | base64 -d 2>/dev/null || true)"
fi
[ -n "$TOKEN" ] || { echo "SUPABASE_ACCESS_TOKEN を設定するか supabase login してください"; exit 1; }
export SUPABASE_ACCESS_TOKEN="$TOKEN"   # supabase CLI もこれを使う

API="https://api.supabase.com/v1/projects/$PROD_REF"
runsql() { # $1 = SQL。Management API の query エンドポイントで postgres 権限実行。
  local body; body="$(jq -Rs '{query: .}' <<<"$1")"
  curl -s -w '\n[HTTP %{http_code}]\n' -X POST "$API/database/query" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$body"
}

# --- secrets 読み出し（値は echo しない） ---
GID="$(grep '^GOOGLE_CLIENT_ID=' "$SECRETS/google_oauth.env" | cut -d= -f2- | tr -d '[:space:]')"
GSEC="$(grep '^GOOGLE_CLIENT_SECRET=' "$SECRETS/google_oauth.env" | cut -d= -f2- | tr -d '[:space:]')"
RKEY="$(grep '^RESEND_API_KEY=' "$SECRETS/resend.env" | cut -d= -f2- | tr -d '[:space:]')"
KEYID="$(basename "$P8" | sed -E 's/AuthKey_(.*)\.p8/\1/')"
PUSH_SECRET="$(openssl rand -hex 24)"
TMPL='<div style="font-family:-apple-system,Helvetica,sans-serif;max-width:480px;margin:0 auto;padding:24px"><h2 style="color:#111">Gymnee サインイン</h2><p>確認コード:</p><p style="font-size:32px;font-weight:700;letter-spacing:6px;color:#111">{{ .Token }}</p><p style="color:#555">このコードをアプリに入力してください（1時間で失効します）。</p><p style="color:#999;font-size:12px">心当たりがない場合はこのメールを無視してください。</p></div>'

echo "▶ 1/4 スキーマ適用（setup_all.sql）"
runsql "$(cat "$ROOT/supabase/setup_all.sql")"

echo "▶ 2/4 Auth 設定（Apple/Google/email/SMTP/redirect/OTP）"
BODY="$(jq -n --arg gid "$GID" --arg gsec "$GSEC" --arg rkey "$RKEY" --arg tmpl "$TMPL" '{
  external_apple_enabled:true, external_apple_client_id:"com.gymnee.app",
  external_google_enabled:true, external_google_client_id:$gid, external_google_secret:$gsec,
  external_email_enabled:true,
  smtp_host:"smtp.resend.com", smtp_port:"465", smtp_user:"resend", smtp_pass:$rkey,
  smtp_admin_email:"noreply@gymnee.app", smtp_sender_name:"Gymnee",
  uri_allow_list:"gymnee://auth-callback",
  mailer_templates_magic_link_content:$tmpl, mailer_templates_confirmation_content:$tmpl,
  mailer_subjects_magic_link:"Gymnee のサインインコード", mailer_subjects_confirmation:"Gymnee のサインインコード"
}')"
curl -s -w '\n[HTTP %{http_code}]\n' -X PATCH "$API/config/auth" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$BODY" | jq -c '{message}' 2>/dev/null || true

echo "▶ 3/5 Edge Function: send-push デプロイ＋secrets（APNS_HOST=本番）"
supabase functions deploy send-push --project-ref "$PROD_REF"
supabase secrets set --project-ref "$PROD_REF" \
  APNS_KEY="$(cat "$P8")" APNS_KEY_ID="$KEYID" APNS_TEAM_ID=PG5P26J3W2 \
  APNS_BUNDLE_ID=com.gymnee.app APNS_HOST=api.push.apple.com PUSH_SHARED_SECRET="$PUSH_SECRET"

echo "▶ 4/5 Edge Function: plan-workouts（AIワークアウト計画）"
supabase functions deploy plan-workouts --project-ref "$PROD_REF"
if [ -s "$SECRETS/gemini.env" ]; then
  GKEY="$(grep '^GEMINI_API_KEY=' "$SECRETS/gemini.env" | cut -d= -f2- | tr -d '[:space:]')"
  supabase secrets set --project-ref "$PROD_REF" \
    GEMINI_API_KEY="$GKEY" GEMINI_MODEL=gemini-3.5-flash GEMINI_API_VERSION=v1
else
  echo "  ⚠ secrets/gemini.env が無いため GEMINI_API_KEY 未設定。AI計画を使うなら後で:"
  echo "    supabase secrets set --project-ref $PROD_REF GEMINI_API_KEY=<key> GEMINI_MODEL=gemini-3.5-flash GEMINI_API_VERSION=v1"
fi

echo "▶ 5/5 push_config 投入"
runsql "insert into public.push_config (id, send_push_url, push_secret) values (1, 'https://$PROD_REF.supabase.co/functions/v1/send-push', '$PUSH_SECRET') on conflict (id) do update set send_push_url=excluded.send_push_url, push_secret=excluded.push_secret;"

cat <<EOF

✅ 自動部分は完了。残りの手動（docs/production-setup.md）:
   ★ Google Cloud の OAuth client に redirect 追加: https://$PROD_REF.supabase.co/auth/v1/callback
   ★ Config/Secrets.prod.xcconfig を差し替え:
       SUPABASE_HOST = $PROD_REF.supabase.co
       SUPABASE_KEY  = <prod の anon/publishable key>
   ★ 商品カタログ(products)を投入（fetch_rakuten_catalog.py / dev からコピー）
   → 検証: OTP受信 / Google authorize 302 / SiwA / プッシュ（配布ビルドで）
EOF
