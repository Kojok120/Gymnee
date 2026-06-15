# Gymnee

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
- **P7 コマース**：商品/カート/注文、ゴール連動レコメンド、補給ロギング→在庫リマインド、決済（Stub）

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

## 後差し込み / 未確定（要件定義書 §9）
本実装は外部依存を抽象/Stub の背後に隔離している。実接続には以下が必要：
- **Supabase**（§9-2 画像ストレージ含む）：`SyncEngine`/Storage 実装を差し込む（現状ローカルのみ）
- **Sign in with Apple**：有償 Apple Developer アカウント + entitlement（`AuthProviding` 実装を追加）
- **Stripe 決済**：`PaymentProvider` 実装（API キー）
- **HealthKit / App Group（Widget・Watch 共有）**：実機は HealthKit Capability と App Group entitlement の付与が必要
- **watchOS**：当環境は watchOS SDK 未インストールのため未ビルド検証（ターゲットは構成済み・iOSビルドからは隔離）
- **要決定**：ジムプリセット範囲(§9-3)・コマースのフルフィルメント(§9-4)・サブスク採用と決済経路(§9-5)・SNS公開範囲(§9-6、enum で両対応済み)
