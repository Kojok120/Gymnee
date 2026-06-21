# Gymnee Supabase バックエンド

要件定義書 §3〜§4 / §7 に基づくスキーマ・RLS・Storage・関数。**アフィリエイト移行後**（注文/カート/決済テーブルは廃止、`products` は送客カタログ）。

## 適用順
SQL Editor もしくは `psql` で番号順に流す。

```bash
export DATABASE_URL="postgresql://postgres:[PASSWORD]@db.[PROJECT_REF].supabase.co:5432/postgres"
psql "$DATABASE_URL" -f migrations/0001_schema.sql
psql "$DATABASE_URL" -f migrations/0002_rls.sql
psql "$DATABASE_URL" -f migrations/0003_storage.sql
psql "$DATABASE_URL" -f migrations/0004_functions.sql
psql "$DATABASE_URL" -f seed.sql          # 商品カタログ（任意）
```

Supabase CLI 派なら `supabase/migrations/` をそのまま `supabase db push` に載せられるよう番号命名済み。

## テーブル（19）
profiles / gyms / gym_equipment / visits / visit_partners / workouts / exercises /
workout_exercises / exercise_sets / routines / routine_exercises / personal_records /
body_metrics / progress_photos / follows / feed_items / products / supply_logs / subscriptions

> 旧 `orders` / `order_items` はアフィリエイト方式のため作成しない。

## RLS 要点
- ユーザー所有データ … 本人(`user_id = auth.uid()`)のみ全権。
- マスタ（gyms / exercises）… プリセット(`created_by IS NULL`)は全員参照、ユーザー作成分は作成者のみ更新。
- 公開コンテンツ（progress_photos / feed_items）… `visibility` と `is_following()` で参照可否を判定（§9-6 は enum で両対応）。
- products … 全員参照、書込はサービスロールのみ（クライアントからカタログ改変不可）。

## Storage バケット
| bucket | public | 用途 | パス規約 |
|---|---|---|---|
| `progress-photos` | no | 体型写真（厳格に本人のみ） | `<uid>/<file>` |
| `visit-photos` | no | チェックイン写真（本人のみ・署名URL配信） | `<uid>/<file>` |
| `avatars` | yes | プロフィール画像（公開読取） | `<uid>/<file>` |

## アプリ側の設定（環境別 xcconfig）
`Config/Secrets.example.xcconfig` を複製して `Config/Secrets.dev.xcconfig`（Debug）/ `Secrets.prod.xcconfig`（Release）を作り、値を入れる（gitignore 済み）。

```
SUPABASE_HOST = [PROJECT_REF].supabase.co   # スキーム(https://)は付けない
SUPABASE_KEY  = sb_publishable_...           # Publishable key か Legacy anon。Secret key は不可
```

- 認証は **Sign in with Apple**（Supabase Auth の Apple プロバイダを有効化）＋メール。
- アカウント削除は RPC `delete_account()` を呼ぶ（auth.users 削除 → 全データ CASCADE）。

## 残作業（このSQL適用後）
1. Supabase ダッシュボードで Apple / Email プロバイダを有効化（SiwA は Services ID・キー登録が必要）。
2. APNs 用に通知を使うなら別途キー登録。
3. 商品カタログを実 ASP（楽天 / バリューコマース）の計測タグ付きURLへ差し替え。
4. アプリの `SyncEngine` 実装（`SupabaseSyncEngine`）を有効化して push/pull を結線。
