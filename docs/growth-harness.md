# グロース分析ハーネス (Gymnee)

Gymnee のトラフィックとファネルを継続的に「分析 → 改善」で回す仕組み。
決定論的な収集はスクリプト、判断はエージェント、繰り返し起動はコマンド、状態は台帳、と役割を分ける。
nihongo-web の同型ハーネスを Gymnee のデータソース (Supabase 本番 + App Store Connect) に合わせて移植したもの。

**注意(2026-07)**: 現時点のユーザーは開発者・TestFlightテスターのみ。数値は配管の動作確認として扱い、
本格的なファネル分析・実験運用は App Store 公開後に開始する。

## ループ(毎サイクル回すもの)

```
① 収集 → ② 診断 → ③ 処方 → ④ 実装 → ⑤ 測定 ─┐
   ↑                                            │
   └────────────────────────────────────────────┘
```

| ステージ | 道具 | 実体 |
|---|---|---|
| ① 収集 | script | `scripts/analytics/snapshot.mjs` (Supabase + App Store → `analytics/snapshots/<JST日時>.json`) |
| ② 診断 | agent | `growth-analyst` (ファネル構築・ボトルネック特定。処方はしない) |
| ③ 処方 | agent | `growth-strategist` (実在ファイルに紐づく実験を `analytics/experiments.md` に起票) |
| ④ 実装 | 人 / 実装エージェント | 起票された変更を最小差分で実装・リリース |
| ⑤ 測定 | command | `/growth-measure <id>` (前後スナップショット比較で勝敗判定 → 台帳更新) |
| オーケストレーション | command | `/growth-report` (①→②→レポート保存) |
| 状態 (記憶) | repo files | `analytics/snapshots/` `analytics/campaigns.md` `analytics/experiments.md` `docs/growth-kpi-tree.md` |

## 週次の回し方(手元運用)

```
# 1. 今週の状態を収集して診断レポートを出す
/growth-report

# 2. 第1ボトルネックの実験を起票する
/growth-experiment

# 3. 実験を実装・リリースする(人 or 実装エージェント)

# 4. 施策(ASO変更/SNS/紹介等)をやったら都度記録する
/campaign-log X で beta 募集ポスト

# 5. 計測窓が終わったら効果測定する
/growth-measure EXP-20260723-xxxx
```

`/growth-report` は内部で `node scripts/analytics/snapshot.mjs` を叩く。依存ゼロの Node スクリプト (Swift ビルドとは無関係)。

## データソース

| ソース | 何が取れるか | 認証 | 状態 |
|---|---|---|---|
| Supabase 本番 (Management API) | 登録以降の全ファネル・活動・課金・ソーシャル (集計値のみ) | `SUPABASE_ACCESS_TOKEN` (env or macOS keychain の `supabase login` トークン) | 稼働 |
| App Store Connect | DL / 更新 / サブスク (トップ・オブ・ファネル) | 共有 ASC キー (`~/.appstoreconnect/private_keys/` + `secrets/.env` の KEY_ID/ISSUER) | 稼働 (DL は `ASC_VENDOR_NUMBER` 設定で有効) |

### Supabase 収集の仕組み (集計値のみ・RLS 回避)

- **経路**: Supabase Management API のクエリエンドポイント `POST https://api.supabase.com/v1/projects/{ref}/database/query` に **読み取り専用の集計 SQL** を投げる。これは `postgres` 権限で走り RLS を無視できるため、集計値だけを 1 往復で取れる。
- **認証**: `SUPABASE_ACCESS_TOKEN` (PAT `sbp_...`)。env 優先、無ければ macOS keychain の `supabase login` トークンを流用 (`scripts/setup_supabase_prod.sh` と同じ読み方)。→ **git に新しい秘密を足さない**。
- **PROD_REF**: env `SUPABASE_PROD_REF` 優先、無ければ `secrets/.env` の `SUPABASE_PROD_HOST` (`ibtrbymfmxrruuwuzell.supabase.co` → `ibtrbymfmxrruuwuzell`) から抽出。
- **安全策**: SQL は **SELECT / WITH のホワイトリスト**。DML/DDL キーワードを含むクエリは実行前に拒否。COUNT / date_trunc グルーピングの**集計値のみ**を取り、生の個人データ・メール・生 ID は一切取らない。全指標ゼロでも壊れない (配信直後のデータが薄い状態を前提)。

トークンが見つからない時は `snapshot.mjs` が `supabase.configured:false` + error を載せて best-effort 継続する。
恒久化するなら env に `SUPABASE_ACCESS_TOKEN=sbp_...` を置くか、`supabase login` 済みのマシンで実行する。

### App Store の DL 取得

`pull-appstore.mjs` は共有 ASC キーで認証・app 情報・Sales/Subscription まで取得する。
日別 DL には vendor number が要る (ASC「支払いと財務レポート」左上の 8 桁)。
`ASC_VENDOR_NUMBER` を env / `secrets/.env` / `~/.config/growth/asc.env` のいずれかに置くと DL が有効化される (3 アプリ共通値)。

## スナップショットの契約

`snapshot.mjs` は nihongo 準拠:
- 標準出力の**最終行 = 保存パス 1 行** (後段コマンドが拾いやすい)。進捗・要約は標準エラー。
- どちらのソースも **best-effort** (失敗しても `error` フィールドを載せて続行)。
- 出力は `{ schema, generatedAtUtc, windowDays, appstore, supabase }`。**集計値のみ** (個人情報なし)。
- ファイル名は JST 日時 (`YYYY-MM-DD_HHMM.json`)。同日複数回実行しても上書きしない。字句順=時系列順。
- `analytics/snapshots/` は **gitignore 済み**でローカル蓄積とする (履歴は手元に貯める)。

## 保留中: 帰属計装(次サイクルの候補)

今は「どの DL がどの施策由来か」を機械的に追えない。`campaigns.md` は相関の手掛かりに留まる。本格化する際の低コスト案:

1. **Apple キャンペーンリンク**: `?ct=x-beta-0723` のような campaign token 付き App Store リンクを SNS/QR に使う → ASC の「キャンペーン」で施策別 DL が割れる。コード変更ゼロ。
2. **招待コード / InviteLink**: `Gymnee/Core/Domain/InviteLink.swift` に紹介元を載せ、`profiles` に取得元を残す。紹介ループの計測に直結。
3. **オンボ内 "どこで知りましたか"**: `Gymnee/Features/Onboarding/SetupOnboardingView.swift` に 1 問追加 + `profiles` に acquisition_source 列。一次データで確実。

## 将来の自動化

現状は手元で週 1 コマンド運用。クラウド/launchd で週次自動実行にする場合、`SUPABASE_ACCESS_TOKEN` (PAT は失効しない限り再ログイン不要) と ASC の静的資格情報を実行環境の env に配線すれば headless 化できる。
まず手運用で 2〜3 週回して、フィールド名・KPI ツリーが安定してから自動化する (nihongo の方針を踏襲)。

## ファイル一覧

```
scripts/analytics/
  pull-appstore.mjs   # ASC DL/サブスク収集 (JWT 認証・依存ゼロ・3アプリ共通)
  pull-supabase.mjs   # 本番 Supabase ファネル収集 (Management API・SELECT 集計のみ・依存ゼロ)
  snapshot.mjs        # 上記を束ねて JST 日時付き JSON 保存
analytics/
  snapshots/*.json    # 収集履歴 (集計値のみ・個人情報なし・gitignore 済みでローカル蓄積)
  reports/*.md        # growth-analyst の診断レポート
  campaigns.md        # マーケ施策台帳
  experiments.md      # 実験 PDCA 台帳
.claude/agents/
  growth-analyst.md   # 診断
  growth-strategist.md# 処方 (起票)
.claude/commands/
  growth-report.md    # 収集+診断
  growth-experiment.md# 起票
  growth-measure.md   # 効果測定
  campaign-log.md     # 施策記録
docs/
  growth-kpi-tree.md  # KPI 定義・ベースライン・目標
  growth-harness.md   # このファイル
```
