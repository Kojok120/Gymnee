# Gymnee プロジェクト エージェント指示

このファイルはコーディングエージェント（Claude / Codex 等）向けのガイドです。
CLAUDE.md は `@AGENTS.md` をimportするスタブ。指示の編集は AGENTS.md のみで行う。
配下に `AGENTS.md` がある場合は、その領域固有ルールもあわせて従ってください。

## 共通規約(要約)

- 応答・コメント・コミットは日本語(Conventional Commits 1.0.0、絵文字なし)
- 優先順位: 正しさ・セキュリティ・データ整合性 > フレームワーク制約 > KISS > YAGNI > DRY
- シークレットはGitに入れない。詳細な共通規約はClaude側グローバル設定(~/.claude/CLAUDE.md)に集約

## プロジェクト概要

Gymnee は SwiftUI ベースの **iOS ネイティブ筋トレアプリ**です。
カレンダーを起点に、ワークアウトの記録・共有・購買（アフィリエイト送客）が 1 アプリで完結します。
ローカル（SwiftData）を正とする**オフラインファースト**設計で、Supabase をリモート同期・認証・ストレージ・AI 計画のバックエンドに使います。本体アプリに加え、ウィジェット（WidgetKit / Live Activity）、watchOS アプリ、App Intents（Siri）を含みます。

このファイルはリポジトリ全体に共通する実装原則を定義します。配下に `AGENTS.md` が存在する場合は、その領域固有ルールもあわせて従ってください。

## 技術スタック

- **言語 / UI**: Swift 6（strict concurrency）+ SwiftUI（iOS 18+ / watchOS 10+）
- **状態管理**: Observation（`@Observable` / `@State` / `@Environment`）+ SwiftData の `@Query`
- **ローカル永続化**: SwiftData（`Gymnee/Core/Persistence/GymneeSchema.swift`）＝ローカルの正
- **プロジェクト生成**: XcodeGen（`project.yml` から `.xcodeproj` を生成。`.xcodeproj` は生成物で gitignore 済み）
- **バックエンド**: Supabase（PostgREST / GoTrue 認証 / Storage / Edge Functions）。外部 SDK を足さず `SupabaseClient`（URLSession の薄い自前クライアント・依存ゼロ）で叩く
- **認証**: Sign in with Apple / メール OTP / Google OAuth（PKCE）。トークンは Keychain
- **iOS 機能**: WidgetKit + Live Activity（ActivityKit）、App Intents（Siri）、HealthKit、CoreLocation（ジオフェンス自動チェックイン）、WatchConnectivity、APNs
- **AI**: Supabase Edge Function（`plan-workouts` → Gemini）でワークアウト計画を生成
- **CI/CD**: GitHub Actions（`ci.yml` でビルド/テスト、`testflight.yml` で `main` push → TestFlight 配信）

## 公式ベストプラクティス

以下は、このプロジェクトの採用技術に直接関係する公式方針です。

### Swift / Swift Concurrency

- Swift 6 の strict concurrency を前提にする。共有可変状態は `actor` に閉じ込め、UI に触れる型・サービスは `@MainActor` にする
- 並行境界を越える値は `Sendable` を満たす。`@unchecked Sendable` や不要な `nonisolated(unsafe)` で逃げない
- `async/await` を基本にし、`Task` のキャンセル・寿命を意識する（View 消滅時に走り続けるタスクを残さない）
- `Int(Double)` 変換前に `isFinite` を確認するなど、トラップ（クラッシュ）を生む値変換に注意する

### アーキテクチャ（オフラインファースト）

- **SwiftData がローカルの正**。同期は `SyncEngine` / `LocalSyncEngine`（outbox にためる）で抽象化し、コンフリクトは last-write-wins（`ConflictResolver`）で解く
- **DI は `AppEnvironment`**（`@MainActor @Observable`）に各サービス（auth / sync / location / health / notifications / subscription / calendar 等）を集約し `.environment(...)` で注入する。サービスを View 内で直接 new しない
- **ドメインロジックは純粋関数として `Gymnee/Core/Domain/` に置く**（`OneRepMax` / `PRDetector` / `VolumeCalculator` / `PlateCalculator` / `StreakCalculator` / `RecoveryAnalyzer` / `ConflictResolver` 等）。新しいビジネスルールはここに切り出してユニットテストを書く
- 本体 / Widget / Watch の共有コードは `Shared/` `SharedActivity/` `SharedConnectivity/` に置く

### Supabase（自前 REST クライアント）

- リモートアクセスは `SupabaseClient`（`Gymnee/Core/Sync/SupabaseClient.swift`）経由に統一する。新しい外部 SDK を安易に足さない
- 認可は **RLS** が基準（ユーザー所有データは `user_id = auth.uid()` のみ全権）。クライアント側で権限を握らない
- キーの扱い: anon / publishable key は `apikey` ヘッダ、ユーザー JWT は存在する時だけ `Authorization: Bearer`。**Secret key はアプリに埋めない**
- アクセストークン期限切れ（401）は refresh_token で一度だけ更新して再試行する。refresh はローテーションするので新トークンを必ず Keychain に保存し直す

## Gymnee での具体的判断基準

- 画面の責務を崩さない
  - `Gymnee/App`: アプリ起動・ルーティング・テーマ・DI 組み立て
  - `Gymnee/Core`: モデル / 永続化 / 同期 / 認証 / ドメイン / 各種サービス（外部連携）
  - `Gymnee/Features/*`: 機能ごとの画面・ViewModel・UI
  - `Features/Shared/Components.swift`: 共通 UI 部品
- 新しい helper / service を作る前に、`Gymnee/Core/Services` や既存サービスに同責務がないか確認する
- ビジネスルールは View や ViewModel に直書きせず、`Core/Domain/` の純粋関数へ切り出してテストする
- ソースファイルを追加・削除・移動したら **`xcodegen generate` を再実行**する。`.xcodeproj`（pbxproj）を手で編集しない
- デザインは `Gymnee/App/Theme.swift` のトークン経由で当てる（色のハードコード禁止）。予約アクセント **Gymnee Lime `#C6FF3D`** は達成・アクティブ状態（完了セット / ストリーク / PR）にのみ使う
- 問題を局所化して直せるなら、まず局所修正を選ぶ。将来の一般化より現在のユースケースの可読性・保守性を優先する

## Supabase スキーマ / マイグレーション

- スキーマ変更は `supabase/migrations/` に**番号順**の SQL で追加する
- 追加した SQL は **必ず `supabase/setup_all.sql` にも同じ内容を番号順で反映**し、dev Supabase プロジェクトへ Management API / `psql` で適用する（このリポジトリの `.claude` フック・運用ルール）
- **全ユーザーテーブルに RLS を必須**とする。マスタ（gyms / exercises のプリセット = `created_by IS NULL`）は全員参照・作成者のみ更新、公開コンテンツは `visibility` + `is_following()` で判定
- Storage バケットのパスは `<uid>/<file>` 規約（RLS で本人のみ書込）。private バケット（progress-photos / visit-photos）は署名/認証付き GET で配信

## コーディング規約

### 認証とセキュリティ

- 認証は `AuthService` / `AuthProviding` 抽象経由（Sign in with Apple / メール OTP / Google OAuth PKCE）
- アクセストークン・refresh トークンは **Keychain** に保存する。ログや例外メッセージにトークンを出さない
- 認可は Supabase の **RLS** が基準。クライアント由来の `user_id` を検証なしにサーバー操作へ流さない
- Secret は `Config/Secrets.{dev,prod}.xcconfig`（gitignore 済み、`Secrets.example.xcconfig` を複製して用意）に置く

### データ操作

- ローカルは SwiftData（`modelContext`）、リモートは `SupabaseClient` 経由に統一する
- 変更は outbox（`SyncEngine`）に積み、コンフリクトは LWW で解決する。同期順序に依存関係がある場合は親（例: `exercises`）を先に送る
- N+1 / 過剰取得を避け、差分 pull（`updated_at` 基準）を活かす

### コンポーネント設計

- SwiftUI View は小さく保ち、状態は `@Observable` モデルへ寄せる
- 依存は `@Environment(AppEnvironment.self)` で受け取り、View 内でサービスを直接生成しない
- 共通 UI は `Features/Shared/Components.swift`、色・タイポ・モーションは `Theme.swift` のトークンを使う

## レビュー方針

- 通常の PR はコードレビューと静的確認（ビルド / テスト）を行う
- `main` への PR は **TestFlight 配信に直結**するため、本番反映の安全性を基準に重要度を判定する（セキュリティ事故、データ破損、クラッシュ誘発、互換性破壊、リリース阻害を `Critical` / `Major` として扱う）

## Git 運用

- 作業は `feature/*`（または `fix/*` / `chore/*`）ブランチで行い、PR で `main` にマージする（`dev` ブランチ運用は無し）
- `main` への push は `testflight.yml` により TestFlight へ自動配信される。`main` に直接 push せず PR を通す
- ブランチ整理が必要になったら `/sync-clean`（ユーザーコマンド）で `main` を origin に同期し、それ以外のローカルブランチを削除する

## 主要ディレクトリ

```text
project.yml                 XcodeGen 定義（app / widgets / watch / tests）
Gymnee/
├── App/                    起動・ルーティング・テーマ・DI（AppEnvironment）
├── Core/
│   ├── Models/             SwiftData モデル
│   ├── Persistence/        GymneeSchema / seed
│   ├── Sync/               SupabaseClient / SyncEngine / SyncStore
│   ├── Auth/               AuthService / Keychain
│   ├── Domain/             純粋ドメインロジック（ユニットテスト対象）
│   ├── Location / Health / Services / Intents / Subscription
└── Features/*              機能ごとの画面・ViewModel・UI
Shared/                     App Group 共有スナップショット（app/widget/watch 共通）
SharedActivity/             Live Activity 属性（ActivityKit）
SharedConnectivity/         WatchConnectivity 共通
GymneeWidgets/              WidgetKit 拡張（ウィジェット + Live Activity）
GymneeWatch/                watchOS アプリ
GymneeTests/                ドメインロジックのユニットテスト
supabase/                   migrations / setup_all.sql / functions / seed
Config/                     環境別シークレット xcconfig（gitignore）
```

## 開発コマンド

```bash
xcodegen generate          # project.yml から Gymnee.xcodeproj を生成（ソース増減のたびに再実行）
# ビルド（iPhone シミュレータ）
xcodebuild -project Gymnee.xcodeproj -scheme Gymnee \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
# ユニットテスト（ドメインロジック）
xcodebuild -project Gymnee.xcodeproj -scheme Gymnee \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

DEBUG 限定の検証ハーネス（製品ビルドには含まれない）:

```bash
xcrun simctl launch <device> com.gymnee.app.dev -gymneeDemo -gymneeScreen <name>
# Debug ビルドの bundle id は .dev サフィックス付き（com.gymnee.app は Release）
# name: gym / checkin / workout / logger / profile / social / shop / analytics / body / share
```

## 環境変数 / シークレット

iOS の `.env` 相当は **xcconfig** で扱う。`Config/Secrets.example.xcconfig` を複製して用意する（いずれも gitignore 済み）。

- `Config/Secrets.dev.xcconfig`（Debug ビルド）/ `Config/Secrets.prod.xcconfig`（Release ビルド）で **Debug→dev / Release→prod** が自動切替
- 主なキー:
  - `SUPABASE_HOST` — `[PROJECT_REF].supabase.co`（スキームは付けない）
  - `SUPABASE_KEY` — Publishable key か Legacy anon（Secret key は不可）
  - `GOOGLE_IOS_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` — Google サインイン（カレンダー連携）
- xcconfig → ビルド設定 → `Info.plist` → 実行時に `SupabaseConfig` が Bundle から読む。未設定ならローカルのみで動作（オフラインファースト）

## デプロイ

- **注意(2026-07)**: GitHub Actions はアカウント単位で課金停止中(2026-08見直し)。復帰までは `testflight.yml` は起動しないため、TestFlight 配信はローカルで archive → export → upload を実行する
- **TestFlight**: `main` への push で `testflight.yml` が起動し、ビルド → 署名 → App Store Connect へ配信(Actions復帰後)
- **CI**: `ci.yml` でビルド / テストを実行
- 署名・プロビジョニング・ASC / APNs 鍵などの秘匿値は CI のシークレットおよび `Config/Secrets.*.xcconfig` で管理し、リポジトリに含めない
- watchOS は環境により SDK 未導入で未ビルド検証の場合がある（ターゲット構成済み・iOS ビルドからは隔離）

## グロース分析ハーネス

獲得〜継続〜課金〜ソーシャルのファネルを継続的に「分析 → 改善」で回す仕組み。詳細は [`docs/growth-harness.md`](docs/growth-harness.md)、指標定義は [`docs/growth-kpi-tree.md`](docs/growth-kpi-tree.md)。

- 収集: `node scripts/analytics/snapshot.mjs`（本番 Supabase + App Store → `analytics/snapshots/*.json`）。依存ゼロの Node スクリプトで Swift ビルドとは無関係
  - Supabase は Management API `/database/query` に **SELECT 集計のみ**を投げ（RLS 回避・集計値のみ・個人情報なし）、認証は `SUPABASE_ACCESS_TOKEN`（env or macOS keychain の `supabase login` トークン）を流用
  - App Store は共有 ASC キーで DL / 更新 / サブスクを best-effort 取得
- 診断: agent `growth-analyst` / 処方: agent `growth-strategist`
- 運用: `/growth-report`（収集+診断）→ `/growth-experiment`（起票）→ 実装 → `/growth-measure`（効果測定）。施策は `/campaign-log` で記録
- 台帳: `analytics/campaigns.md`（施策）/ `analytics/experiments.md`（実験 PDCA）。`analytics/snapshots/` は gitignore 済みでローカル蓄積
- 現状は手元で週 1 コマンド運用。配信直後で N が 1 桁のため率で断定せず実数で語る
