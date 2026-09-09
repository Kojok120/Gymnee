import Foundation

/// プリセット種目ごとの初期表示重量（履歴なし時のルーラー中央値）と重量刻み。
///
/// 出典（2026-07 リサーチ、2026-09 拡充）:
/// - 初期重量: Strength Level の初心者基準値（男女中間を10回の作業重量に換算し、
///   日本人平均体格と日本語トレーナー監修記事の目安で下方補正）。軽すぎるくらいが安全側。
/// - 刻み: 日本のジム器具の実態。ダンベル=1kg刻みラック（10kg超は2kg刻みだが1kgは両者の
///   上位互換）、バーベル/スミス=プレート1.25kg×2=2.5kg、マシン/ケーブル=スタック5kg
///   （2.5kg補助や7kg/lb系は長押しキーパッドの自由入力で受ける）、ケトルベル=4kg。
///   ケーブル片側（ファンクショナルトレーナー等の 2:1 プーリーを片手で引く種目）=実効1.25kg
///   （issue #114。片側でスタック 2.5kg 刻みが半分になる）。
///
/// 名前一致で引き、無ければ器具既定（`fallbackStep` / `fallbackStartWeight`）へフォールバック。
enum ExerciseDefaults {
    struct Entry: Equatable {
        /// 履歴なし時の初期表示（kg。片側種目はダンベル1本あたり、両側計はバー込み総重量）。
        let startWeight: Double
        /// ルーラーの刻み（kg）。
        let weightStep: Double
    }

    static func entry(for name: String) -> Entry? { byName[name] }

    /// 名前一致しない種目（カスタム種目）の刻み。器具と数え方から決める純粋関数。
    /// ケーブルは片側なら 1.25kg（ファンクショナルトレーナーの実効刻み）、それ以外はスタック 5kg。
    static func fallbackStep(equipment: EquipmentType, weightMode: WeightMode) -> Double {
        switch equipment {
        case .cable: return weightMode == .perSide ? 1.25 : 5
        case .machine: return 5
        case .kettlebell: return 4
        case .dumbbell: return 1
        case .barbell, .bodyweight, .other: return 2.5
        }
    }

    /// 名前一致しない種目（カスタム種目）の履歴なし時の初期重量。
    /// 自重系は符号付き（補助スタイルの種目は補助側 −10 から始める）。ケーブル片側は片手分なので控えめ。
    static func fallbackStartWeight(
        equipment: EquipmentType, weightMode: WeightMode,
        measurementType: MeasurementType, loadMode: LoadMode
    ) -> Double {
        if measurementType == .bodyweight {
            return loadMode == .assisted ? -10 : 0
        }
        switch equipment {
        case .barbell: return 20
        case .dumbbell: return 5
        case .machine: return 10
        case .cable: return weightMode == .perSide ? 5 : 10
        case .kettlebell: return 8
        case .bodyweight: return 0
        case .other: return 10
        }
    }

    private static let byName: [String: Entry] = [
        // 胸
        "ベンチプレス": .init(startWeight: 30, weightStep: 2.5),
        "インクラインベンチプレス": .init(startWeight: 20, weightStep: 2.5),
        "デクラインベンチプレス": .init(startWeight: 30, weightStep: 2.5),
        "ダンベルプレス": .init(startWeight: 8, weightStep: 1),
        "インクラインダンベルプレス": .init(startWeight: 8, weightStep: 1),
        "ダンベルフライ": .init(startWeight: 6, weightStep: 1),
        "ダンベルプルオーバー": .init(startWeight: 10, weightStep: 1),
        "チェストプレス": .init(startWeight: 15, weightStep: 5),
        "インクラインチェストプレス": .init(startWeight: 15, weightStep: 5),
        "デクラインチェストプレス": .init(startWeight: 20, weightStep: 5),
        "ペックフライ": .init(startWeight: 15, weightStep: 5),
        "ケーブルクロスオーバー": .init(startWeight: 5, weightStep: 1.25),
        "スミスマシンベンチプレス": .init(startWeight: 20, weightStep: 2.5),
        "スミスマシンインクラインベンチプレス": .init(startWeight: 15, weightStep: 2.5),
        // 背中
        "デッドリフト": .init(startWeight: 40, weightStep: 2.5),
        "ベントオーバーロウ": .init(startWeight: 20, weightStep: 2.5),
        "ワンハンドロウ": .init(startWeight: 12, weightStep: 1),
        "Tバーロウ": .init(startWeight: 20, weightStep: 2.5),
        "ラットプルダウン": .init(startWeight: 25, weightStep: 5),
        "シーテッドロウ": .init(startWeight: 20, weightStep: 5),
        // ハイロウ/ローロウはプレートロード（片腕ずつ）のため 2.5kg 刻み。
        "ハイロウ": .init(startWeight: 20, weightStep: 2.5),
        "ローロウ": .init(startWeight: 20, weightStep: 2.5),
        "ケーブルプルオーバー": .init(startWeight: 15, weightStep: 5),
        "バーベルシュラッグ": .init(startWeight: 40, weightStep: 2.5),
        "ダンベルシュラッグ": .init(startWeight: 14, weightStep: 1),
        // 脚
        "スクワット": .init(startWeight: 30, weightStep: 2.5),
        "フロントスクワット": .init(startWeight: 30, weightStep: 2.5),
        "スミスマシンスクワット": .init(startWeight: 25, weightStep: 2.5),
        "ゴブレットスクワット": .init(startWeight: 12, weightStep: 1),
        "ブルガリアンスクワット": .init(startWeight: 8, weightStep: 1),
        "ランジ": .init(startWeight: 6, weightStep: 1),
        "レッグプレス": .init(startWeight: 50, weightStep: 5),
        "ハックスクワット": .init(startWeight: 40, weightStep: 5),
        "レッグエクステンション": .init(startWeight: 20, weightStep: 5),
        "レッグカール": .init(startWeight: 15, weightStep: 5),
        "ルーマニアンデッドリフト": .init(startWeight: 30, weightStep: 2.5),
        "カーフレイズ": .init(startWeight: 20, weightStep: 5),
        "ヒップアダクション": .init(startWeight: 30, weightStep: 5),
        // 肩（弱い部位なので特に控えめ。レイズ系は2.5kg刻みでは粗すぎるため1kg、マシン/ケーブルも細かめ）
        "ショルダープレス": .init(startWeight: 10, weightStep: 5),
        "ダンベルショルダープレス": .init(startWeight: 6, weightStep: 1),
        "バーベルショルダープレス": .init(startWeight: 20, weightStep: 2.5),
        "スミスマシンショルダープレス": .init(startWeight: 15, weightStep: 2.5),
        "アーノルドプレス": .init(startWeight: 6, weightStep: 1),
        "サイドレイズ": .init(startWeight: 3, weightStep: 1),
        "ケーブルサイドレイズ": .init(startWeight: 5, weightStep: 1.25),
        "マシンサイドレイズ": .init(startWeight: 10, weightStep: 2.5),
        "フロントレイズ": .init(startWeight: 3, weightStep: 1),
        "ケーブルフロントレイズ": .init(startWeight: 5, weightStep: 2.5),
        "リアレイズ": .init(startWeight: 3, weightStep: 1),
        "リアデルトフライ": .init(startWeight: 15, weightStep: 5),
        "フェイスプル": .init(startWeight: 15, weightStep: 5),
        "アップライトロウ": .init(startWeight: 15, weightStep: 2.5),
        // 腕（バーベル系はEZバー相当の10kg起点）
        "バーベルカール": .init(startWeight: 10, weightStep: 2.5),
        "プリーチャーカール": .init(startWeight: 10, weightStep: 2.5),
        "ダンベルカール": .init(startWeight: 5, weightStep: 1),
        "インクラインダンベルカール": .init(startWeight: 5, weightStep: 1),
        "コンセントレーションカール": .init(startWeight: 5, weightStep: 1),
        "ハンマーカール": .init(startWeight: 5, weightStep: 1),
        "マシンアームカール": .init(startWeight: 10, weightStep: 2.5),
        "ケーブルカール": .init(startWeight: 10, weightStep: 5),
        "トライセプスプレスダウン": .init(startWeight: 10, weightStep: 5),
        "スカルクラッシャー": .init(startWeight: 10, weightStep: 2.5),
        "キックバック": .init(startWeight: 3, weightStep: 1),
        "オーバーヘッドエクステンション": .init(startWeight: 10, weightStep: 1),
        "ナローベンチプレス": .init(startWeight: 25, weightStep: 2.5),
        // 腹
        "ケーブルクランチ": .init(startWeight: 10, weightStep: 5),
        "アブドミナルクランチ": .init(startWeight: 20, weightStep: 5),
        "トーソローテーション": .init(startWeight: 20, weightStep: 5),
        // 臀部
        "ヒップスラスト": .init(startWeight: 20, weightStep: 2.5),
        "ヒップアブダクション": .init(startWeight: 30, weightStep: 5),
        "ケーブルキックバック": .init(startWeight: 5, weightStep: 1.25),
        // 全身
        "ケトルベルスイング": .init(startWeight: 12, weightStep: 4),
        "クリーン&ジャーク": .init(startWeight: 20, weightStep: 2.5),
        "パワークリーン": .init(startWeight: 30, weightStep: 2.5),
        // 自重（符号付き一本軸: −補助/0自重/＋加重）。初心者は補助が必要なことが多いため
        // 補助側を初期中央に（Strength Level 初心者基準: 懸垂 男-13/女-22、ディップス 男-8/女-20）。
        // 刻みはルーラー側の区分定義（補助5kg/加重2.5kg）を使うため step は補助側の値。
        "懸垂": .init(startWeight: -15, weightStep: 5),
        "ディップス": .init(startWeight: -10, weightStep: 5),
    ]
}
