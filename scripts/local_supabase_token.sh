#!/usr/bin/env bash
#
# ローカル Supabase（docs/local-dev.md）にメールでサインインし、access token を標準出力に出す。
# RLS の確認用。2 人分取り、互いの行が見えない・書けないことを curl で確かめる。
#
# ローカル既定のメールはサインインのリンクだけで 6 桁のコードが入らない（native ではテンプレートを
# 差し替えられない）ので、Mailpit に届いたリンクのトークンで verify する。初回はユーザーを作る。
# 接続先がローカル（127.0.0.1 / localhost）でなければ何もせず終わる。
#
# usage: scripts/local_supabase_token.sh <email>
#   例: A=$(scripts/local_supabase_token.sh a@example.test)
#       curl -s "$API/rest/v1/body_metrics" -H "apikey: $KEY" -H "Authorization: Bearer $A"
set -euo pipefail

EMAIL="${1:-}"
[ -n "$EMAIL" ] || { echo "usage: $0 <email>" >&2; exit 1; }
for c in supabase jq curl; do command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }; done
cd "$(dirname "$0")/.."

ST="$(supabase status --output-format json 2>/dev/null || true)"   # 実験版スタックでは -o json は空
API="$(jq -r '.env.API_URL // empty' <<<"$ST" 2>/dev/null || true)"
KEY="$(jq -r '.env.PUBLISHABLE_KEY // empty' <<<"$ST" 2>/dev/null || true)"
MAIL="$(jq -r '.env.MAILPIT_URL // empty' <<<"$ST" 2>/dev/null || true)"
case "$API" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "ローカル Supabase が起動していない（supabase start）。API_URL=${API:-なし}" >&2; exit 1 ;;
esac
case "$MAIL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Mailpit の URL が取れない: ${MAIL:-なし}" >&2; exit 1 ;;
esac

Q="to:$EMAIL"
curl -s -o /dev/null -X DELETE "$MAIL/api/v1/search" --get --data-urlencode "query=$Q"   # 古いメールを消す
curl -s -f -o /dev/null -X POST "$API/auth/v1/otp" -H "apikey: $KEY" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg e "$EMAIL" '{email: $e, create_user: true}')" \
  || { echo "OTP の送信に失敗（送信回数の上限の可能性）" >&2; exit 1; }

ID=""
for _ in $(seq 1 20); do
  ID="$(curl -s "$MAIL/api/v1/search" --get --data-urlencode "query=$Q" | jq -r '.messages[0].ID // empty')"
  [ -n "$ID" ] && break
  sleep 0.5
done
[ -n "$ID" ] || { echo "メールが届かない: $EMAIL" >&2; exit 1; }

LINK="$(curl -s "$MAIL/api/v1/message/$ID" | jq -r '.Text' | grep -oE 'token=[^& )]+&type=[a-z_]+' | head -1)"
TOKEN_HASH="$(sed -E 's/^token=([^&]+)&.*/\1/' <<<"$LINK")"
TYPE="$(sed -E 's/.*&type=//' <<<"$LINK")"
[ -n "$TOKEN_HASH" ] || { echo "メールにサインインのリンクが無い" >&2; exit 1; }

AT="$(curl -s -X POST "$API/auth/v1/verify" -H "apikey: $KEY" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg t "$TOKEN_HASH" --arg ty "$TYPE" '{type: $ty, token_hash: $t}')" | jq -r '.access_token // empty')"
[ -n "$AT" ] || { echo "verify に失敗" >&2; exit 1; }
printf '%s\n' "$AT"
