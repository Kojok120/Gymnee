import Foundation

/// ジムの出所。`preset` = アプリ同梱、`user` = ユーザー自己登録。
enum GymSource: String, Codable, CaseIterable, Sendable {
    case preset
    case user
}

/// セット種別（§6.5）。
enum SetType: String, Codable, CaseIterable, Sendable {
    case normal
    case warmup
    case drop
    case superset

    var label: String {
        switch self {
        case .normal: return "通常"
        case .warmup: return "ウォームアップ"
        case .drop: return "ドロップ"
        case .superset: return "スーパーセット"
        }
    }
}

/// PR の種別（§4.2 / §6.5）。
enum PRType: String, Codable, CaseIterable, Sendable {
    case maxWeight = "max_weight"
    case maxReps = "max_reps"
    case est1RM = "est_1rm"
    case maxVolume = "max_volume"

    var label: String {
        switch self {
        case .maxWeight: return "最大重量"
        case .maxReps: return "最大レップ"
        case .est1RM: return "推定1RM"
        case .maxVolume: return "最大ボリューム"
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

/// 注文ステータス（§4.5）。
enum OrderStatus: String, Codable, CaseIterable, Sendable {
    case cart
    case pending
    case paid
    case shipped
    case delivered
    case cancelled

    var label: String {
        switch self {
        case .cart: return "カート"
        case .pending: return "支払い待ち"
        case .paid: return "支払い済み"
        case .shipped: return "発送済み"
        case .delivered: return "配達済み"
        case .cancelled: return "キャンセル"
        }
    }
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
    case core
    case glutes
    case fullBody = "full_body"

    var label: String {
        switch self {
        case .chest: return "胸"
        case .back: return "背中"
        case .legs: return "脚"
        case .shoulders: return "肩"
        case .biceps: return "二頭"
        case .triceps: return "三頭"
        case .core: return "体幹"
        case .glutes: return "臀部"
        case .fullBody: return "全身"
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
