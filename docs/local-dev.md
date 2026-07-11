# ローカル開発（Debug ビルド × ローカル Supabase）

dev/beta の Supabase プロジェクトは削除したため、Debug ビルドのバックエンドは
**`supabase start`（Docker 上のローカル Supabase 一式）** を接続先にする。クラウド課金ゼロで
Postgres / Auth(GoTrue) / Storage / RLS / マイグレーションを実機同等に検証できる。

## 前提
- Docker Desktop 起動中
- Supabase CLI（`supabase --version`）

## 起動
```bash
cd <repo>
supabase start          # 初回は Docker イメージを取得（数分）。migrations/*.sql と seed.sql を適用して起動
supabase status         # API URL と anon key を確認（下の xcconfig と一致させる）
```
- API URL は 127.0.0.1:54421（config.toml で既定+100 の専用ポートブロックを割当。他ローカル Supabase と共存可）
- anon key は `supabase status` の Publishable（`sb_publishable_...`・ローカル既定・非機密）

## アプリ（Debug）から繋ぐ
`Config/Secrets.dev.xcconfig`（gitignore 済み）:
```
SUPABASE_HOST = 127.0.0.1:54421
SUPABASE_KEY  = <supabase status の anon key>
```
- `SUPABASE_HOST` にスキームは付けない（xcconfig は `//` をコメント扱い）。host が 127.0.0.1:54421 等の
  ローカル/プライベート宛なら **アプリが自動で http を使う**（`SupabaseConfig.scheme(for:)`）。
- iOS シミュレータは Mac の localhost を共有するので 127.0.0.1:54421 で届く（実機は Mac の LAN IP を使う）。
- HTTP 接続は ATS の `NSAllowsLocalNetworking`（ローカル宛のみ許可）で通す。公開ホストには無影響。
- **`EnvironmentGuard`**: Debug(`.dev` bundle)はローカル/非本番ホストのみ許可、本番ホストは不可。
  Release(無印 bundle)は本番ホストのみ許可（ローカルにも繋がない）。

起動していない時は接続失敗するが、オフラインファーストによりローカルのみで動作する（無害）。

## マイグレーションの検証（ステージング代替）
```bash
# migrations/*.sql を編集 → setup_all.sql に同内容を番号順で反映（運用ルール）
supabase db reset       # ローカル DB を作り直して全 migration + seed を再適用（壊れないか確認）
```
検証が通ったら prod（`ibtrbymfmxrruuwuzell`）へ Management API で適用する（`supabase db push` は使わない）。

## 制約
- 外部 OAuth（Apple / Google）はローカルでは動かない。auth はメール OTP（ローカルは Inbucket が
  メールを受ける・`supabase status` の Inbucket URL）で検証する。
- Edge Functions はローカルでも起動するが、secrets（APNs/Gemini/Resend）未設定のため通知/AI は限定的。
- 停止は `supabase stop`（`--no-backup` でボリューム破棄）。
