---
description: Gymnee グロース週次レポート。スナップショットを収集し growth-analyst で診断、日付付きレポートを保存する
argument-hint: "[windowDays=30]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(node scripts/analytics/snapshot.mjs:*), Bash(node scripts/analytics/pull-supabase.mjs:*), Bash(node scripts/analytics/pull-appstore.mjs:*), Bash(ls:*), Task
---

Gymnee アプリの獲得ファネルを収集 → 診断 → レポート保存する、グロースループの心拍コマンド。手元で週 1 回叩く運用。

## 手順

1. **収集**: `node scripts/analytics/snapshot.mjs ${1:-30}` を実行する。
   - Supabase 本番 (Management API) は `SUPABASE_ACCESS_TOKEN` (env or macOS keychain の `supabase login` トークン) で自動取得。App Store は共有 ASC キーで best-effort。
   - 標準出力の最後の 1 行が保存先パス (`analytics/snapshots/<JST日時>.json`)。標準エラーに要約が出る。
   - 失敗したら原因 (Supabase アクセストークン未取得 / ネットワーク / ASC ロール) を提示して停止する。トークンが見つからない場合は「env に `SUPABASE_ACCESS_TOKEN=sbp_...` を設定するか `supabase login`」と案内。

2. **診断**: `growth-analyst` サブエージェントを Task で起動する。プロンプトは「最新スナップショットを診断し、構造化レポートを返せ。ファイルは書くな」。
   - analyst は最新+前回スナップショット・campaigns.md・experiments.md・docs/growth-kpi-tree.md を読んで診断する。

3. **保存**: analyst が返した markdown を `analytics/reports/<今日のJST日付>.md` に保存する (Write)。ファイル冒頭に生成日時とスナップショット窓を付ける。

4. **要約**: ユーザーに 5 行以内で要約する:
   - 今週の新規登録数と前回比
   - 最大のボトルネック (実数付き)
   - データの限界 (小 N / 帰属未計装 / 同期遅延) を 1 行
   - 次アクション: 「第 1 ボトルネックの実験を起票するなら `/growth-experiment`」

## 注意

- これは全体運用の起点。**診断まで**が責務で、施策提案・実装はしない。
- コホート (新規登録者) と全体活動 (テスト/知人アカウント混入あり) を混同しないよう、analyst の注記をそのまま尊重する。
- Gymnee は配信直後で N が 1 桁。率で断定せず実数で語る。
- スナップショット JSON は集計値のみ (個人情報なし) だが、`analytics/snapshots/` は gitignore 済みでローカル蓄積とする。
