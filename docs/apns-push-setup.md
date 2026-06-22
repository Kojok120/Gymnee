# APNs プッシュ配信セットアップ手順

「フレンドのチェックイン通知」を実配信するための手順。コード側（アプリの受信ハンドラ・
`device_tokens` 登録・`aps-environment` entitlement・Edge Function `send-push`・DB トリガー
`0008_push_on_visit.sql`）は実装済み。残りはあなたの Apple / Supabase アカウントでの設定作業です。

配信経路:
`visits` insert → DB トリガー `notify_friend_checkin`（pg_net）→ Edge Function `send-push`
→ フォロワーの `device_tokens` を引いて APNs(`/3/device/<token>`)へ送信。

---

## 1. Apple Developer Portal

1. **App ID の Push 有効化**: Certificates, Identifiers & Profiles → Identifiers → `com.gymnee.app`
   → Capabilities で **Push Notifications** にチェック → Save。
2. **APNs Auth Key (.p8) を作成**: Keys → ＋ → 名前を付け **Apple Push Notifications service (APNs)**
   にチェック → Continue → Register → **AuthKey_XXXXXXXXXX.p8 をダウンロード**（再DL不可・厳重保管）。
   - 控える値: **Key ID**（10桁、ファイル名の XXXX 部）/ **Team ID**（`PG5P26J3W2`）。
3. Xcode は自動署名のままで OK。`aps-environment` は entitlements に `development` で入れてある。
   配布アーカイブ時は Xcode が `production` に自動昇格する。

> dev 署名（Xcode 実行 / Development）で動かす間は `APNS_HOST=api.sandbox.push.apple.com`。
> **TestFlight / App Store 配布ビルドは本番 APNs**（`api.push.apple.com`）を使う点に注意。

## 2. Supabase: Edge Function のデプロイ

```bash
supabase link --project-ref bdeaeykruwxazdoewxmg   # 本番化時は prod の ref に
supabase functions deploy send-push
```

シークレットを設定（`.p8` は中身全文を渡す）:

```bash
PUSH_SECRET=$(openssl rand -hex 24)          # 後で DB 設定にも使う
supabase secrets set \
  APNS_KEY="$(cat AuthKey_XXXXXXXXXX.p8)" \
  APNS_KEY_ID=XXXXXXXXXX \
  APNS_TEAM_ID=PG5P26J3W2 \
  APNS_BUNDLE_ID=com.gymnee.app \
  APNS_HOST=api.sandbox.push.apple.com \
  PUSH_SHARED_SECRET="$PUSH_SECRET"
```

（`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` は Supabase が自動注入するので設定不要）

## 3. Supabase: DB 設定（トリガー → Function の接続情報）

migration `0008_push_on_visit.sql` は `public.push_config`（1行・RLS で不可視）を作る。
適用後、その1行を upsert する（SQL エディタで `<...>` を実値に置換して実行）:

```sql
insert into public.push_config (id, send_push_url, push_secret)
values (
  1,
  'https://bdeaeykruwxazdoewxmg.supabase.co/functions/v1/send-push',
  '<PUSH_SHARED_SECRET と同じ値>'
)
on conflict (id) do update
  set send_push_url = excluded.send_push_url,
      push_secret   = excluded.push_secret;
```

> 接続情報を GUC（`alter database ... set`）に置かないのは、Supabase の `postgres` ロールでは
> `permission denied to set parameter`（42501）になるため。RLS 有効＋ポリシー無しの設定テーブルに持ち、
> security definer のトリガー関数だけが読む。クライアントからは参照不可。

## 4. 動作確認

- **Function 単体**（実トークンを 1 つ用意して）:
  ```bash
  curl -i -X POST 'https://<ref>.supabase.co/functions/v1/send-push' \
    -H "X-Push-Secret: $PUSH_SECRET" -H 'Content-Type: application/json' \
    -d '{"event":"friend_checkin","visitId":"<実在するvisitのUUID>"}'
  # → {"sent":N,"stale":0}
  ```
- **E2E**: 実機 A・B を用意し、A が B をフォロー → B がアプリでチェックイン →
  A の端末に「B さんがジムに行きました」が届けば成功。
  - 届かない時の切り分け: `device_tokens` に B のフォロワー(A)の行があるか / `APNS_HOST` が
    ビルドの署名(dev=sandbox / 配布=本番)と一致しているか / Function ログ（`supabase functions logs send-push`）。

## 5. 本番（prod プロジェクト分離時）

- `config.toml` の `project_id` と `app.send_push_url` を prod の ref に差し替え。
- `APNS_HOST=api.push.apple.com` に変更（配布ビルドは本番 APNs）。
- それ以外（.p8 / Key ID / Team ID）は同一で可。

## 仕様メモ

- バックフィル暴発防止: トリガーは `visited_at` が直近10分以内の insert だけ通知する
  （過去来店の一括同期では送らない）。
- 失効トークン掃除: APNs が 410 を返した token は Function 側で `device_tokens` から削除。
- 拡張余地: 本文の `type: "friend_checkin"` / `visitorId` を使い、タップ時の画面遷移（ディープリンク）を後付け可能。
