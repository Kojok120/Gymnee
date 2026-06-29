import Foundation

/// ジムの出所。`preset` = アプリ同梱、`user` = ユーザー自己登録。
enum GymSource: String, Codable, CaseIterable, Sendable {
    case preset
    case user
}

/// PR の種別（§4.2 / §6.5）。計測タイプごとに意味のある指標へ絞る。
/// - ウェイト種目: maxWeight ＋ est1RM の 2 本。
/// - 自重種目: maxReps。
/// - 時間種目: maxDuration（最長秒数）。
enum PRType: String, Codable, CaseIterable, Sendable {
    case maxWeight = "max_weight"
    case est1RM = "est_1rm"
    case maxReps = "max_reps"
    case maxDuration = "max_duration"
    case minAssist = "min_assist"      // 補助種目: 最小補助（軽いほど強い）

    var label: String {
        switch self {
        case .maxWeight: return "最大重量"
        case .est1RM: return "推定1RM"
        case .maxReps: return "最大レップ"
        case .maxDuration: return "最長時間"
        case .minAssist: return "最小補助"
        }
    }

    /// 計測タイプ別トロフィー/バッジのアイコン（祝福演出・フィード・実績で共用）。
    var symbol: String {
        switch self {
        case .maxWeight: return "dumbbell.fill"
        case .est1RM: return "bolt.fill"
        case .maxReps: return "flame.fill"
        case .maxDuration: return "stopwatch.fill"
        case .minAssist: return "minus.circle.fill"
        }
    }

    /// PR 値の表示用フォーマット（種別ごとに単位が違う）。各 View の重複を集約。
    func formatted(_ value: Double) -> String {
        switch self {
        case .maxWeight, .est1RM, .minAssist: return String(format: "%.1f kg", value)
        case .maxReps: return "\(Int(value)) reps"
        case .maxDuration:
            let s = Int(value)
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }
}

/// 公開範囲（§4.3 / §6.11、§9-6 は enum で両対応）。
enum Visibility: String, Codable, CaseIterable, Sendable {
    case `private`
    case friends
    case `public`

    var label: String {
        switch self {
        case .private: return "非公開"
        case .friends: return "友達限定"
        case .public: return "公開"
        }
    }
}

/// フィード生成元の種別（§4.4）。
enum FeedItemType: String, Codable, CaseIterable, Sendable {
    case visit
    case pr
    case workout
}

/// サブスク階層（§4.5、採用可否は §9-5 で要決定）。
enum SubscriptionTier: String, Codable, CaseIterable, Sendable {
    case free
    case pro
    case elite

    var label: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .elite: return "Elite"
        }
    }
}

enum SubscriptionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case cancelled
    case expired
}

/// 部位（部位バランス・リカバリービュー・ボリューム集計に使用）。
enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest
    case back
    case legs
    case shoulders
    case biceps
    case triceps
    case abs
    case core
    case glutes
    case cardio
    case fullBody = "full_body"
    case other

    var label: String {
        switch self {
        case .chest: return "胸"
        case .back: return "背中"
        case .legs: return "脚"
        case .shoulders: return "肩"
        case .biceps: return "二頭"
        case .triceps: return "三頭"
        case .abs: return "腹"
        case .core: return "体幹"
        case .glutes: return "臀部"
        case .cardio: return "有酸素"
        case .fullBody: return "全身"
        case .other: return "その他"
        }
    }
}

/// 器具種別。
enum EquipmentType: String, Codable, CaseIterable, Sendable {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case kettlebell
    case other

    var label: String {
        switch self {
        case .barbell: return "バーベル"
        case .dumbbell: return "ダンベル"
        case .machine: return "マシン"
        case .cable: return "ケーブル"
        case .bodyweight: return "自重"
        case .kettlebell: return "ケトルベル"
        case .other: return "その他"
        }
    }
}

/// 重量の数え方（§6.5）。ダンベル等で片側の重量を入力するか、合計（両側）を入力するか。
enum WeightMode: String, Codable, CaseIterable, Sendable {
    case both       // 両側・合計（バーベル等）
    case perSide    // 片側（ダンベル等。実効ボリュームは ×2 相当）

    var label: String {
        switch self {
        case .both: return "両側"
        case .perSide: return "片側"
        }
    }
    /// バッジ用の短縮表記。
    var short: String {
        switch self {
        case .both: return "両"
        case .perSide: return "片"
        }
    }
}

/// 自重種目の荷重スタイル（種目ごとの既定。bodyweight のときだけ意味を持つ）。
/// 懸垂等で「荷重(自重＋kg)」と「補助(自重−kg / バンド・アシストマシン)」を明示的に区別する。
/// 記録される `weight` は常に正の大きさで、符号/意味はこの mode が解釈する。
enum LoadMode: String, Codable, CaseIterable, Sendable {
    case none        // 自重のみ（腕立て等）
    case weighted    // 荷重（自重＋kg。加重懸垂等）
    case assisted    // 補助（自重−kg。アシスト懸垂等）

    var label: String {
        switch self {
        case .none: return "自重のみ"
        case .weighted: return "荷重"
        case .assisted: return "補助"
        }
    }
    /// 重量軸の入力を持つか（自重のみは reps だけ）。
    var hasLoadInput: Bool { self != .none }
    /// 入力値（正の大きさ）の符号表現。荷重=＋, 補助=−, 自重=空。
    var signPrefix: String {
        switch self {
        case .none: return ""
        case .weighted: return "＋"
        case .assisted: return "−"
        }
    }
    /// 記録カード等の重量軸ラベル。
    var loadAxisLabel: String {
        switch self {
        case .none: return "自重"
        case .weighted: return "荷重 ＋"
        case .assisted: return "補助 −"
        }
    }
    /// セットの加重大きさ(magnitude≥0)を表示用テキストに。荷重「＋20kg」/ 補助「補助20kg」/ 自重「自重」。
    func loadText(_ magnitude: Double) -> String {
        switch self {
        case .none: return "自重"
        case .weighted: return magnitude > 0 ? String(format: "＋%gkg", magnitude) : "自重"
        case .assisted: return magnitude > 0 ? String(format: "補助%gkg", magnitude) : "自重"
        }
    }
}

/// 計測タイプ（記録リデザイン）。種目をどの軸で記録するか。
/// - weight: 重量 × reps（バーベル/マシン等）
/// - bodyweight: 自重（任意の加重 × reps。懸垂・ディップス等）
/// - time: 時間（秒。プランク等）
enum MeasurementType: String, Codable, CaseIterable, Sendable {
    case weight
    case bodyweight
    case time
    /// 有酸素（距離km ＋ 時間分）。ランニング/ウォーキング/バイシクル等。
    case cardio

    var label: String {
        switch self {
        case .weight: return "ウェイト"
        case .bodyweight: return "自重"
        case .time: return "時間"
        case .cardio: return "有酸素"
        }
    }

    /// 重量（加重）軸を持つか。time / cardio は false。
    var hasWeightAxis: Bool { self == .weight || self == .bodyweight }
    /// reps 軸を持つか。time / cardio は false（秒・距離/時間で記録）。
    var hasRepsAxis: Bool { self == .weight || self == .bodyweight }
}

/// 投稿へのリアクション種別（§6.11 ゲーミフィケーション）。いいねのみ。
/// 投稿への応援リアクション（筋トレ文脈の絵文字）。1ユーザー1投稿につき1種別（タップで切替/取消）。
/// `like` は旧データ互換のため先頭に残す。サーバ側 CHECK 制約と同期させること（migration 0018）。
enum ReactionKind: String, Codable, CaseIterable, Sendable {
    case like
    case strong
    case fire
    case clap

    var label: String {
        switch self {
        case .like: return "いいね"
        case .strong: return "ナイスバルク"
        case .fire: return "熱い"
        case .clap: return "ナイス"
        }
    }
    /// 表示用絵文字（バーのチップに使う）。
    var emoji: String {
        switch self {
        case .like: return "❤️"
        case .strong: return "💪"
        case .fire: return "🔥"
        case .clap: return "👏"
        }
    }
    /// SF Symbol フォールバック（旧UI互換）。
    var icon: String {
        switch self {
        case .like: return "heart.fill"
        case .strong: return "figure.strengthtraining.traditional"
        case .fire: return "flame.fill"
        case .clap: return "hands.clap.fill"
        }
    }
}
