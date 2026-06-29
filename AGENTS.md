# Gymnee プロジェクト エージェント指示

このファイルはコーディングエージェント（Claude / Codex 等）向けのガイドです。
ルートの `CLAUDE.md` と `AGENTS.md` は常に同一内容を維持する（どちらかを更新したら必ず他方も同じ内容に揃える）。
配下に `AGENTS.md` がある場合は、その領域固有ルールもあわせて従ってください。

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

## 実装原則の優先順位

実装判断に迷った場合は、次の優先順で決定してください。

1. **正しさ・セキュリティ・データ整合性**
2. **フレームワーク制約・既存アーキテクチャとの整合**
3. **KISS**
4. **YAGNI**
5. **DRY**

補足:

- `DRY` は常に最優先ではありません。責務が安定していて共有価値がある重複だけに適用します。
- 早すぎる抽象化よりも、正しく安全で追いやすい実装を優先します。

## KISS / YAGNI / DRY

### KISS

- 1 変更 1 責務を基本にする
- 認証、権限判定、同期、UI 表示の責務を同じ型や View に混ぜない
- 小さな View、小さな関数、素直な条件分岐、短いデータフローを優先する
- 使わない抽象化、設定、ラッパー、ヘルパーを増やさない

### YAGNI

- 今の要件で使わない拡張ポイント、未使用 property、オプション引数、将来用フラグを追加しない
- 未確定な複数ユースケースのために先回りした汎用化をしない
- 将来必要になるかもしれない、だけを理由に型や API を広げない

### DRY

- 安定したドメインルール（1RM / ボリューム / PR 判定など）、認可条件、共通クエリ、定数は 1 箇所に寄せる
- 見た目が似ているだけで責務が違うコードは共通化しない
- 「同じ入力・同じ責務・同じ変更理由を共有する重複」だけを DRY の対象にする
- 共有後に呼び出し側が複雑になるなら、共通化を見送る

## 公式ベストプラクティス

以下は、このプロジェクトの採用技術に直接関係する公式方針です。

### Swift / Swift Concurrency

- Swift 6 の strict concurrency を前提にする。共有可変状態は `actor` に閉じ込め、UI に触れる型・サービスは `@MainActor` にする
- 並行境界を越える値は `Sendable` を満たす。`@unchecked Sendable` や不要な `nonisolated(unsafe)` で逃げない
- `async/await` を基本にし、`Task` のキャンセル・寿命を意識する（View 消滅時に走り続けるタスクを残さない）
- `Int(Double)` 変換前に `isFinite` を確認するなど、トラップ（クラッシュ）を生む値変換に注意する

### SwiftUI / Observation

- View の `body` は pure に保ち、副作用を持たせない。派生値は state に持たず `body` 内で計算する
- 状態は最小にし、`@Observable` モデルへ寄せる。props を `@State` にミラーして同期させない
- `.task` / `.onChange` は外部システム同期に使い、派生計算やイベント処理には使わない
- View は小さく分割し、`@Environment(AppEnvironment.self)` で依存を受け取る（後述の DI）
- SwiftData は `@Query` で読み、書き込みは `modelContext` 経由。重い処理を `body` に置かない

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

## 作業時のホスピタリティ

メイン作業で触れたコード（読み書きしたファイル）に明確な改善余地を見つけた場合は、見て見ぬふりをせず以下を行う。

- ユーザーに報告する: **何を見つけたか / なぜ直す価値があるか / 影響範囲とリスク** を簡潔に伝える
- 修正する: 改善は本来のタスクとは別の論理単位として扱い、**別コミット**で記録する（メイン作業のコミットに混ぜない）
- 改善対象の例: リファクタリング機会（重複・責務混在・命名）、パフォーマンス問題（`body` 内の重い再計算、不要な再描画、同期の無駄な往復）、デッドコード、未使用の型・property、安全でない並行処理、誤った値変換（クラッシュ要因）、トークン未経由の色直書きなど
- スコープは触れたファイル周辺に限定する: 触れていない無関係なファイルを巻き込んだ大規模リファクタはやらない（YAGNI / 1 コミット 1 責務）
- ユーザーから「今回は触らないで」と指示があれば改善は見送り、`TODO` コメントやメモを残して次回拾えるようにする
- 既存のテストやビルドが落ちる改善はやらない: 改善コミットの前後で `xcodebuild ... build` と `... test` が通ることを確認する

## コーディング規約

### 言語とスタイル

- コメントおよびドキュメントは**日本語**で記述する
- コミットメッセージは **Conventional Commits 1.0.0** に準拠し、日本語で記述する
  - 例: `feat: チェックイン写真の近隣ジム自動選択を追加`
- 絵文字は使わない
- ヘッダー行の末尾に句点を付けない

### 認証とセキュリティ

- 認証は `AuthService` / `AuthProviding` 抽象経由（Sign in with Apple / メール OTP / Google OAuth PKCE）
- アクセストークン・refresh トークンは **Keychain** に保存する。ログや例外メッセージにトークンを出さない
- 認可は Supabase の **RLS** が基準。クライアント由来の `user_id` を検証なしにサーバー操作へ流さない
- Secret は `Config/Secrets.{dev,prod}.xcconfig`（gitignore 済み）に置き、`Secrets.example.xcconfig` を複製して使う。コードや Git に秘匿値を含めない

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
- 重要度区分は `Critical` / `Major` / `Minor` / `Trivial`

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
xcrun simctl launch <device> com.gymnee.app -gymneeDemo -gymneeScreen <name>
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

- **TestFlight**: `main` への push で `testflight.yml` が起動し、ビルド → 署名 → App Store Connect へ配信
- **CI**: `ci.yml` でビルド / テストを実行
- 署名・プロビジョニング・ASC / APNs 鍵などの秘匿値は CI のシークレットおよび `Config/Secrets.*.xcconfig` で管理し、リポジトリに含めない
- watchOS は環境により SDK 未導入で未ビルド検証の場合がある（ターゲット構成済み・iOS ビルドからは隔離）
