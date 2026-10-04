#!/bin/bash
# Supabase の migration を Docker なしで検証する。
# 一時 PostgreSQL を立て、stub.sql → 対象 migration を2回（冪等性の確認）→ *_test.sql の順に流す。
#   使い方: bash scripts/sqltest/run.sh supabase/migrations/0040_party_boss.sql scripts/sqltest/party_boss_test.sql
set -euo pipefail
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@16/bin}"
DIR="$(cd "$(dirname "$0")" && pwd)"
MIGRATION="$1"; TEST="$2"
DATA="$(mktemp -d)"; PORT="${PORT:-55433}"
cleanup() { "$PGBIN/pg_ctl" -D "$DATA" stop -m fast >/dev/null 2>&1 || true; rm -rf "$DATA"; }
trap cleanup EXIT
"$PGBIN/initdb" -D "$DATA" -U postgres -A trust >/dev/null 2>&1
"$PGBIN/pg_ctl" -D "$DATA" -o "-p $PORT -k $DATA" -l "$DATA/log" start >/dev/null
sleep 1
psql_run() { "$PGBIN/psql" -h "$DATA" -p "$PORT" -U postgres -q -v ON_ERROR_STOP=1 -X "$@"; }
psql_run -f "$DIR/stub.sql" >/dev/null
psql_run -f "$MIGRATION" 2>&1 | grep -v NOTICE || true
psql_run -f "$MIGRATION" 2>&1 | grep -v NOTICE || true
psql_run -f "$TEST" 2>&1 | grep -E "PASSED|ERROR|assert|FAIL" 
