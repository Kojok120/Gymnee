import Foundation

/// プリセット種目ごとの初期表示重量（履歴なし時のルーラー中央値）と重量刻み。
///
/// 出典（2026-07 リサーチ）:
/// - 初期重量: Strength Level の初心者基準値（男女中間を10回の作業重量に換算し、
///   日本人平均体格と日本語トレーナー監修記事の目安で下方補正）。軽すぎるくらいが安全側。
/// - 刻み: 日本のジム器具の実態。ダンベル=1kg刻みラック（10kg超は2kg刻みだが1kgは両者の
///   上位互換）、バーベル/スミス=プレート1.25kg×2=2.5kg、マシン/ケーブル=スタック5kg
///   （2.5kg補助や7kg/lb系は長押しキーパッドの自由入力で受ける）、ケトルベル=4kg。
///
/// 名前一致で引き、無ければ器具既定（RecordSlots）へフォールバック。
enum ExerciseDefaults {
    struct Entry: Equatable {
        /// 履歴なし時の初期表示（kg。片側種目はダンベル1本あたり、両側計はバー込み総重量）。
        let startWeight: Double
        /// ルーラーの刻み（kg）。
        let weightStep: Double
    }

    static func entry(for name: String) -> Entry? { byName[name] }

    private static let byName: [String: Entry] = [
        // 胸
        "ベンチプレス": .init(startWeight: 30, weightStep: 2.5),
        "インクラインベンチプレス": .init(startWeight: 20, weightStep: 2.5),
        "ダンベルプレス": .init(startWeight: 8, weightStep: 1),
        "チェストプレス": .init(startWeight: 15, weightStep: 5),
        "ペックフライ": .init(startWeight: 15, weightStep: 5),
        "スミスマシンベンチプレス": .init(startWeight: 20, weightStep: 2.5),
        // 背中
        "デッドリフト": .init(startWeight: 40, weightStep: 2.5),
        "ベントオーバーロウ": .init(startWeight: 20, weightStep: 2.5),
        "ラットプルダウン": .init(startWeight: 25, weightStep: 5),
        "シーテッドロウ": .init(startWeight: 20, weightStep: 5),
        // 脚
        "スクワット": .init(startWeight: 30, weightStep: 2.5),
        "スミスマシンスクワット": .init(startWeight: 25, weightStep: 2.5),
        "レッグプレス": .init(startWeight: 50, weightStep: 5),
        "レッグエクステンション": .init(startWeight: 20, weightStep: 5),
        "レッグカール": .init(startWeight: 15, weightStep: 5),
        "ルーマニアンデッドリフト": .init(startWeight: 30, weightStep: 2.5),
        "カーフレイズ": .init(startWeight: 20, weightStep: 5),
        // 肩（弱い部位なので特に控えめ。レイズ系は2.5kg刻みでは粗すぎるため1kg）
        "ショルダープレス": .init(startWeight: 10, weightStep: 5),
        "ダンベルショルダープレス": .init(startWeight: 6, weightStep: 1),
        "スミスマシンショルダープレス": .init(startWeight: 15, weightStep: 2.5),
        "サイドレイズ": .init(startWeight: 3, weightStep: 1),
        "リアレイズ": .init(startWeight: 3, weightStep: 1),
        "アップライトロウ": .init(startWeight: 15, weightStep: 2.5),
        // 腕（バーベル系はEZバー相当の10kg起点）
        "バーベルカール": .init(startWeight: 10, weightStep: 2.5),
        "ダンベルカール": .init(startWeight: 5, weightStep: 1),
        "ハンマーカール": .init(startWeight: 5, weightStep: 1),
        "トライセプスプレスダウン": .init(startWeight: 10, weightStep: 5),
        "スカルクラッシャー": .init(startWeight: 10, weightStep: 2.5),
        // 腹
        "ケーブルクランチ": .init(startWeight: 10, weightStep: 5),
        // 臀部
        "ヒップスラスト": .init(startWeight: 20, weightStep: 2.5),
        // 全身
        "ケトルベルスイング": .init(startWeight: 12, weightStep: 4),
        "クリーン&ジャーク": .init(startWeight: 20, weightStep: 2.5),
        // 加重自重（加重0=自重から。刻みはプレート2.5kg）
        "懸垂": .init(startWeight: 0, weightStep: 2.5),
        "ディップス": .init(startWeight: 0, weightStep: 2.5),
    ]
}
