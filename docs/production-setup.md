# 本番 Supabase プロジェクト セットアップ手順

公開（App Store / 外部テスター本格投入）の**直前**に、dev/beta から独立した**本番 Supabase プロジェクト**を新規作成して切り替えるための手順。
dev/beta プロジェクト（ref `bdeaeykruwxazdoewxmg`）はそのまま開発用に残す。

> なぜ分けるか：本番ユーザーのデータを dev のテスト残骸と隔離する／破壊的マイグレーションの巻き込み防止／鍵の分離／
> APNs 環境を dev=sandbox・prod=production にきれいに分けるため。

大半は `scripts/setup_supabase_prod.sh` で自動化済み。**手動が必要なのは下記の★だけ**。

---

## 再利用 vs 新規（最重要）

| 要素 | prod での扱い |
|---|---|
| APNs `.p8`（`secrets/AuthKey_B5U25H7746_APNs.p8`）/ Key ID `B5U25H7746` / Team ID `PG5P26J3W2` / bundle `com.gymnee.app` | **再利用**（Apple アカウント単位） |
| Resend ドメイン `gymnee.app` / API key（`secrets/.env` の `RESEND_API_KEY`） | **再利用**（ドメイン単位） |
| Gemini API key（AI計画 plan-workouts 用） | **再利用**。prod スクリプトで設定するなら `secrets/.env` に `GEMINI_API_KEY=...` を置く（dev と同じ鍵で可） |
| Google OAuth client id/secret（`secrets/.env` の `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`） | **再利用**。ただし★Google Cloud の Authorized redirect URIs に **prod の callback** を追加する |
| Sign in with Apple の client id（`com.gymnee.app`） | **再利用**（native は id_token 検証なので secret 不要） |
| Supabase project / anon(publishable) key / service role key / DB パスワード | **新規**（プロジェクト作成時に発行） |
| `PUSH_SHARED_SECRET`（DB↔Function 認証） | **新規生成**（スクリプトが自動生成し push_config に投入） |
| `APNS_HOST` | prod = **`api.push.apple.com`**（dev は sandbox） |

---

## 手順

### 0. 前提
- `secrets/` に dev で使ったものがある：`AuthKey_*.p8` と `.env`（統合シークレット: `GOOGLE_*` / `RESEND_API_KEY` / `RAKUTEN_*` / 任意で `GEMINI_API_KEY`）。
- `supabase` CLI がログイン済み、または `SUPABASE_ACCESS_TOKEN`（ダッシュボード → Account → Access Tokens で発行した `sbp_...`）を環境変数に設定。
- `jq` / `openssl` / `supabase` CLI が入っている。

### ★1. 本番プロジェクト作成（ダッシュボード手動）
1. https://supabase.com/dashboard → **New project** → 名前 `gymnee-prod` 等、Region **Tokyo (ap-northeast-1)**、**強い DB パスワード**を設定して安全に保管。
2. 作成後に控える：
   - **Project Ref**（`https://<ref>.supabase.co` の `<ref>`）
   - **anon / publishable key**（Settings → API）
3. （推奨）休止回避のため **Pro プラン**へ（無料は無操作1週間で pause）。

### ★2. Google Cloud に prod の callback を追加（手動）
- https://console.cloud.google.com → APIs & Services → Credentials → OAuth client **Gymnee** を開く
- **Authorized redirect URIs** に追加（dev の分は残したまま）：
  ```
  https://<PROD_REF>.supabase.co/auth/v1/callback
  ```

### 3. セットアップスクリプト実行（自動）
```bash
export SUPABASE_ACCESS_TOKEN=sbp_...        # または supabase login 済みでも可
scripts/setup_supabase_prod.sh <PROD_REF>
```
このスクリプトが流すもの：
- **スキーマ**：`supabase/setup_all.sql`（migrations 0001〜0014 を番号順連結。テーブル / RLS / Storage / `delete_account` RPC / モデレーション / weight_mode / post_reactions / block・gym RLS / プッシュトリガー `0008`・`0013` / follows.notify）
- **Auth 設定**（Management API PATCH）：Apple 有効化、Google 有効化（id/secret）、email 有効化、Resend SMTP、`uri_allow_list=gymnee://auth-callback`、OTP メール本文（6桁 `{{ .Token }}`）
- **Edge Function**：
  - `send-push`（チェックイン通知＋いいね/応援通知）を deploy ＋ secrets（APNS_*、`APNS_HOST=api.push.apple.com`、新規 `PUSH_SHARED_SECRET`）
  - `plan-workouts`（AIワークアウト計画）を deploy ＋ secrets（`secrets/.env` に `GEMINI_API_KEY` があれば `GEMINI_API_KEY`/`GEMINI_MODEL=gemini-3.5-flash`/`GEMINI_API_VERSION=v1`。無ければ警告して後回し）
- **push_config**：prod の Function URL ＋ 新 secret を 1 行 upsert

### ★4. iOS の prod 接続先を差し替え（手動）
`Config/Secrets.prod.xcconfig`（gitignore）を本番プロジェクトに向ける：
```
SUPABASE_HOST = <PROD_REF>.supabase.co
SUPABASE_KEY  = <prod の anon/publishable key>
```
Release ビルド（Archive/TestFlight/App Store）はこの prod を指す。

### ★5. 商品カタログを投入（手動）
本番 DB は空なので、商品(`products`)を入れる：
- `RAKUTEN_APP_ID`/`RAKUTEN_ACCESS_KEY` 付きで `scripts/fetch_rakuten_catalog.py` を実行 → 生成 SQL を本番に流す（dev と同じ手順）。
- または dev の `products` 行をエクスポートして prod に流す。
- `supabase/catalog_add_goal_products.sql`（目標タグ付き商品の追加分）も prod に流す。
- iHerb（A8）承認後の `a8mat` リンクも prod の `products` に反映。

### 6. 検証
- **Auth**：メール（OTP送信→受信→コード検証）/ Google（authorize→302）/ SiwA。
- **Push**：実機で `device_tokens` 登録 → A が B をフォロー → B チェックイン → A に通知。
  - prod は **本番 APNs** なので **配布ビルド（TestFlight/App Store）**で確認すること（Xcode 直挿しの dev 署名は sandbox トークンで届かない）。

---

## 補足：自動化できない項目の理由
- **プロジェクト作成 / DB パスワード / 課金**：ダッシュボード操作（API 不可・要人間判断）。
- **Google callback 追加**：Google Cloud 側の設定（Supabase 外）。
- **xcconfig 差し替え**：ローカルの gitignore ファイル（鍵を含むためコミットしない）。
- **`alter database ... set` は使わない**：Supabase の postgres ロールは権限不足（42501）。接続情報は `push_config` テーブルで保持（dev と同方式）。

## 運用メモ
- Supabase に **DB パスワード無しで SQL を流す**には：`supabase login` 済みなら Management API の `POST /v1/projects/<ref>/database/query`（`Authorization: Bearer <PAT>`、body `{"query":"..."}`）。スクリプトもこれを使用。特権操作（`alter database/role`）だけは 42501 で不可。
- secrets は全て `secrets/`（gitignore：`secrets/` と `*.p8`）に置き、コミットしない。
