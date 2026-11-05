# ローカル開発（Debug ビルド × ローカル Supabase）

dev/beta の Supabase プロジェクトは削除したため、Debug ビルドの接続先とマイグレーションの検証には
**ローカル Supabase（`supabase start`）** を使う。CLI v3 の実験版スタックを有効にしてあり
（config.toml の `[experimental] stack = true`）、Docker が無い Mac では **native ランタイム**
（各サービスを素のプロセスで動かす）で起動する。クラウド課金ゼロで Postgres 17 / Auth(GoTrue) /
PostgREST / Storage / RLS / マイグレーションを本番と同じ形で検証できる。

## 前提
- Supabase CLI v3 以上（`supabase --version`。更新は `brew upgrade supabase/tap/supabase`）。
  v3 では `db` / `migration` 系を対象無しで叩くとローカルを向く（本番は `--remote=<ref>` を付けたときだけ。
  Gymnee は本番に CLI で SQL を流さない）
- Docker は不要（native は Apple silicon・macOS 14 以上）。Docker が動いている Mac では、新しく作るスタックが Docker を使う
- 初回の起動で各サービスの実行ファイル（約 1.9GB、`~/.supabase/cache/stack`）を取得する。
  版は `supabase/supabase.lock` で固定している（コミット対象。上げるときは `supabase stack update`）

## 起動と停止
```bash
supabase start                        # migrations/*.sql と seed.sql を流して起動（初回 40 秒ほど、以後は数秒）
supabase status --output-format json  # .env に API URL・鍵・Mailpit の URL（実験版スタックでは -o json は空）
supabase stop                         # 止める（データは残る）
```
- ポートは config.toml で既定+100 の固定（API 127.0.0.1:54421 / DB 54422 / Studio 54423 / Mailpit 54424）
- **git のブランチごとに別のローカル DB になる**。初めてのブランチで start すると、そのブランチの migrations で
  新しく作る。ポートが固定なので同時に動かせるのは 1 つだけで、ブランチを替えたら
  `supabase stack stop --all` → `supabase start` の順にする
- DB 以外のサービスは最初のリクエストで起動し、使わないと休む
- 要らなくなったブランチの DB は `supabase stack list` で id を見て `supabase stack destroy --stack-id <id> --yes`
  （バックアップ無しで消える。データは `~/.supabase/stacks/<id>/`）

## アプリ（Debug）から繋ぐ
`Config/Secrets.dev.xcconfig`（gitignore 済み）:
```
SUPABASE_HOST = 127.0.0.1:54421
SUPABASE_KEY  = <status の .env.PUBLISHABLE_KEY>
```
- 鍵は `sb_publishable_...`（CLI 既定のローカル用・非機密）
- `SUPABASE_HOST` にスキームは付けない（xcconfig は `//` をコメント扱い）。host が 127.0.0.1:54421 等の
  ローカル/プライベート宛なら **アプリが自動で http を使う**（`SupabaseConfig.scheme(for:)`）。
- iOS シミュレータは Mac の localhost を共有するので 127.0.0.1:54421 で届く（実機は Mac の LAN IP を使う）。
- HTTP 接続は ATS の `NSAllowsLocalNetworking`（ローカル宛のみ許可）で通す。公開ホストには無影響。
- **`EnvironmentGuard`**: Debug(`.dev` bundle)はローカル/非本番ホストのみ許可、本番ホストは不可。
  Release(無印 bundle)は本番ホストのみ許可（ローカルにも繋がない）。
- アプリのメールのコード入力ではサインインできない（下の「制約」）。サインイン無しのゲストのままなら繋がる

起動していない時は接続失敗するが、オフラインファーストによりローカルのみで動作する（無害）。

## マイグレーションの検証（ステージング代替）
```bash
# migrations/*.sql を編集 → setup_all.sql に同内容を番号順で反映（運用ルール）
supabase db reset --yes            # ローカル DB を作り直して全 migration + seed を流し直す（数秒）
supabase db query "select ..."     # 中身の確認（対象無しはローカル）
```
- RLS は 2 人分サインインして curl で確かめる。`scripts/local_supabase_token.sh <email>` が access token を出す
  （初回はユーザーを作る。接続先がローカルでなければ止まる）:
  ```bash
  ST="$(supabase status --output-format json)"; API=$(jq -r .env.API_URL <<<"$ST"); KEY=$(jq -r .env.PUBLISHABLE_KEY <<<"$ST")
  A=$(scripts/local_supabase_token.sh a@example.test); B=$(scripts/local_supabase_token.sh b@example.test)
  curl -s "$API/rest/v1/body_metrics?select=*" -H "apikey: $KEY" -H "Authorization: Bearer $B"   # A の行が見えないこと
  ```
- 冪等性（2 回流しても壊れないか）とアサーション付きの確認は `scripts/sqltest/run.sh`
- 本番との既知の差: ダッシュボードの「新しいテーブルで RLS を自動で有効にする」設定が入れる
  `public.rls_auto_enable()`（event trigger）はローカルに無い。migration 由来ではない
- 確かめ終えたら `supabase db reset --yes` で試しに作ったユーザーと行を消しておく

検証が通ったら prod（`ibtrbymfmxrruuwuzell`）へ Management API で適用する（`supabase db push` は使わない）。

## 制約
- 外部 OAuth（Apple / Google）はローカルでは動かない
- ローカル既定のメールはサインインのリンクだけで、6 桁のコードが入らない。native ではメールのテンプレートを
  差し替えられない（`content_path` 非対応）ので、**Debug アプリのコード入力ではサインインできない**。
  サインインが要る確認は上のスクリプトで token を取って curl で行う（届いたメールは Mailpit http://127.0.0.1:54424）
- Edge Functions はローカルでも起動するが、secrets（APNs/Gemini/Resend）未設定のため通知/AI は限定的
- 実験版の機能なので、CLI の更新でフラグや出力が変わることがある
