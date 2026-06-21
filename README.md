# Gymnee

[![CI](https://github.com/Kojok120/Gymnee/actions/workflows/ci.yml/badge.svg)](https://github.com/Kojok120/Gymnee/actions/workflows/ci.yml)

カレンダーを起点に、筋トレの **記録・共有・購買** が 1 アプリで完結する iOS ネイティブアプリ（Swift / SwiftUI）。
要件定義書 `Gymnee_要件定義書_v0.md` の v1 フルスコープ（P0〜P7）を実装。

## 必要環境
- Xcode 16+（開発は Xcode 26.4 / Swift 6.3 で確認）、iOS 18.0+
- [XcodeGen](https://github.com/yonyz/XcodeGen)（`brew install xcodegen`）— `.xcodeproj` は `project.yml` から生成

## セットアップ / ビルド / テスト
```bash
xcodegen generate                 # project.yml から Gymnee.xcodeproj を生成
# ビルド（iPhone シミュレータ）
xcodebuild -project Gymnee.xcodeproj -scheme Gymnee \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
# ユニットテスト（ドメインロジック 40 本）
xcodebuild -project Gymnee.xcodeproj -scheme Gymnee \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

`Gymnee.xcodeproj` は生成物のため `.gitignore` 済み。ソースを追加したら `xcodegen generate` を再実行する。

## デザイン言語（UI/UX）
世界水準の「わかりやすく・モダン」を目標に、ダークファースト + 単一の予約アクセント **Gymnee Lime `#C6FF3D`** で統一。Hevy / Strong / Whoop / Gentler Streak / iOS 26 Liquid Glass のリサーチに基づく。
- **トークン基盤**（`Gymnee/App/Theme.swift`）：`Color(light:dark:)` で両モード対応のセマンティックカラー（`bg0..bg3` の温かみチャコール、`lime`/`limeFill`/`limeGlow`/`limeSoft`、warning/danger/info/series2、`muscleColor`）。数値は SF Pro **Rounded + monospacedDigit**（`Font.numXL/L/M/S` + `overline`）。spring プリセット（`snappy`/`bouncy`/`smooth`/`timerTick`）。グラデ（`celebration`/`streakRing`/`heroBackground`）。Lime は達成/アクティブ状態（完了セット・ストリーク・PR）にのみ使い特別感を保つ。後方互換エイリアス（`energy`/`accent`/`cardBackground`/`gymneeCard` 等）を維持し未改修画面も自動追従。
- **コンポーネント**（`Features/Shared/Components.swift`）：`StatPill`（丸数字 + オーバーライン + 発光）、`MetricBlock`、`ProgressRing`（角度グラデのストリークリング）、`Chip`、`SectionHeader`（lime バー）、`OverlineLabel`、`GymneePrimary/SecondaryButtonStyle`（プレス縮小 + ハプティクス）。
- **chrome**：`AppAppearance.configure()` でタブ/ナビバーを lime ティント + 丸ゴシックのラージタイトルに。レストタイマーは `.ultraThinMaterial` の浮遊グラスピル（ドレインリング）。
- **シグネチャー**：①ホームのストリークリング + 励まし文（Gentler Streak 流）②大数字 + ゴースト前回値のセットエディタ + 完了で lime 染め + PR メダル（bouncy + `.sensoryFeedback(.success)`）③写真チェックイン完了の祝祭モーメント（bounce + グロー、ReduceMotion 配慮）④共有カードの lime テーマ。
- 検証：iPhone 16 Pro シミュレータでダーク/ライト両対応・ドメインユニットテスト 49 本 green。

## アーキテクチャ
- **オフラインファースト**：SwiftData をローカルの正とし、同期は `SyncEngine` で抽象化（`LocalSyncEngine` は outbox に積むだけの no-op）。コンフリクトは last-write-wins（`ConflictResolver`、§9-7）。
- **認証**：`AuthProviding` 抽象 + `MockAuthProvider`（ローカル）。Sign in with Apple は同 protocol で後差し込み。
- **DI**：`AppEnvironment` に各サービス（auth/sync/location/health）を集約し `.environment` で注入。
- **ドメインロジック**（純粋・ユニットテスト対象、`Gymnee/Core/Domain/`）：
  `OneRepMax`・`PRDetector`・`VolumeCalculator`・`PlateCalculator`・`StreakCalculator`・`RecoveryAnalyzer`・`SupplyAnalyzer`、`ConflictResolver`。

### ディレクトリ
```
project.yml                 XcodeGen 定義（app / widgets / watch / tests）
Gymnee/  App, Core(Models/Persistence/Sync/Auth/Domain/Location/Health/Services/Intents/Commerce), Features/*
Shared/                     App Group 共有スナップショット（app/widget/watch 共通）
SharedActivity/             Live Activity 属性（app/widget 共通・ActivityKit）
GymneeWidgets/              WidgetKit 拡張（ウィジェット + Live Activity）
GymneeWatch/                watchOS アプリ
GymneeTests/                ドメインロジックのユニットテスト
```

## 実装済み（P0〜P7）
- **P0 基盤**：全21エンティティ（SwiftData）、同期/認証抽象、タブ骨格、オンボーディング、プリセット投入
- **P1 コアループ**：カレンダー（月/週・来店マーカー・連続記録・週次ゴール）、写真チェックイン（GPS近隣補完）、ジム管理/図鑑、日別詳細
- **P2 L3ログ**：前回値オートフィル、セット種別/RPE、PR自動検出、推定1RM、ボリューム、プレート計算、ルーティン、種目詳細（推移グラフ）、レストタイマー
- **P3 共有・写真**：共有カード（ImageRenderer・テーマ/項目選択・共有シート）、進捗写真（既定private・月次比較）
- **P4 データ・ヘルス**：HealthKit連携、身体メトリクス、分析（ヒートマップ・頻度・部位バランスレーダー・リカバリービュー）、CSVエクスポート
- **P5 iOS機能**：ウィジェット、Live Activity（レストタイマー）、Siri「ジムに着いた」、ジオフェンス自動チェックイン、watchOSアプリ
- **P6 ソーシャル**：フィード（来店/PR/ワークアウト）、合トレタグ、フォロー、可視性設定
- **P7 コマース（アフィリエイト）**：商品カタログ、ゴール連動レコメンド、補給ロギング→在庫リマインド、提携先（楽天市場/iHerb 等）への送客（`SFSafariViewController`）＋ステマ規制の「広告」開示。カート/注文/決済は廃止。

## 詳細化（追加実装 B1〜B6・追加クレデンシャル不要）
- **ロガー深掘り**：ウォームアップ自動生成（`WarmupCalculator`）、%1RM 目標重量（`StrengthSuggester`）、直近3セッションのインライン履歴、スーパーセット連結（色分け）、種目メモ
- **ルーティン深掘り**：スタータテンプレ（5x5・PPL・全身）、ドラッグ並べ替え、種目別レスト（実セッションのレストタイマーへ反映）
- **分析深掘り**：期間セレクタ（4週/12週/1年）、強度進捗（上位種目の推定1RM推移）、PRタイムライン
- **通知強化**（`NotificationService`）：フォアグラウンド表示、PR達成、予定ワークアウト、連続記録途切れ予告、在庫リマインド
- **チェックイン**：GPSで最寄りジム（種類/場所）を自動選択・手動変更可
- **新規ジム**：リバースジオコーディングで店名/住所を自動補完。**進捗写真**：スライダー式ビフォーアフター

## 検証ハーネス（DEBUG のみ）
起動引数で画面ジャンプ・デモデータ投入が可能（製品ビルドには含まれない）：
```bash
xcrun simctl launch <device> com.gymnee.app -gymneeDemo -gymneeScreen <name>
# name: gym / checkin / workout / logger / profile / social / shop / analytics / body / share
```

## 本番化（バックエンド接続）
ローカル完結の実装に、本番接続の足場を追加済み。鍵を入れると有効化される設計。
- **Supabase スキーマ**：`supabase/migrations/*.sql`（19テーブル＋RLS＋Storage＋トリガ）＋`seed.sql`。`supabase/README.md` 参照。
- **同期エンジン**：`SupabaseClient`（URLSession で PostgREST/Auth を叩く・依存ゼロ）＋`LocalSyncEngine` にリモートの seam。`SwiftDataSyncStore`（`SyncBackingStore`）で19テーブルの SwiftData⇄JSON 変換を実装（LWW・差分pull）。残りは push/pull の起動トリガと実Supabaseでの往復テスト。
- **環境別シークレット（iOS の .env 相当）**：`Config/Secrets.{dev,prod}.xcconfig`（gitignore 済み・`Secrets.example.xcconfig` を複製）に `SUPABASE_HOST`/`SUPABASE_KEY` を設定。**Debug→dev / Release→prod** で自動切替。xcconfig→ビルド設定→Info.plist→実行時 `SupabaseConfig` が読む。未設定ならローカルのみ。
- **Sign in with Apple**：`AuthService.prepareAppleRequest`/`completeSignInWithApple`＋公式 `SignInWithAppleButton`。Supabase 接続時は identityToken を Auth に交換、未接続時はローカルにフォールバック。
- **アカウント削除**：`AuthService.deleteAccount()`→ Supabase RPC `delete_account`（auth.users 削除→CASCADE）。設定の全削除から起動（5.1.1(v)）。
- **APNs**：`AppDelegate`＋`PushTokenCenter`＋`NotificationService.registerForRemotePush()`。トークンは `device_tokens`（migration 0005）へ登録。`aps-environment` entitlement 追加済み（実配信は APNs 鍵が別途必要）。
- **Entitlements**：`Gymnee/Gymnee.entitlements`（applesignin / App Group `group.com.gymnee.app` / HealthKit）。Widget・Watch にも App Group。Developer Portal 側の Capability 有効化が必要。
- **Privacy**：`PrivacyInfo.xcprivacy`（本体/Widget/Watch）。`docs/legal/` にプライバシーポリシー・利用規約ドラフト。
- **watchOS**：当環境は watchOS SDK 未インストールのため未ビルド検証（ターゲット構成済み・iOSビルドからは隔離）。
- **要外部作業**：Apple 審査・ASP（楽天/バリューコマース等）承認・APNs 鍵・App Icon 画像・実機検証。
- **要決定**：ジムプリセット範囲(§9-3)・SNS公開範囲(§9-6、enum で両対応済み)。コマースはアフィリエイト確定によりフルフィルメント(§9-4)/決済(§9-5)は不要化。
