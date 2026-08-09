import Foundation

/// キャラの姿を決めるパラメータ（純粋計算）。描画は `CharacterFigureView` が担当する。
///
/// 体格は**現実の記録の写し**にする。押す力で肩が広くなり、腕力で腕が太くなり、脚力で脚が太くなる。
/// 進化段階は全体の存在感（身長比・オーラ）に効く。装備とスキンは色と重ね描きだけで、体格は変えない。
struct CharacterAppearance: Equatable, Sendable {
    /// 肩幅（0.0〜1.0 の正規化値。描画側が実寸へ変換する）。
    var shoulder: Double
    /// 腕の太さ。
    var arm: Double
    /// 脚の太さ。
    var leg: Double
    /// 胴の厚み（体幹）。
    var torso: Double
    /// オーラの強さ（進化段階で増える）。
    var aura: Double

    /// ステータス（0〜99）と進化段階から体格を組み立てる。
    /// 記録ゼロでも「棒人間」にはせず、最低限の体格から始める（初日でも自分に見えるように）。
    static func make(stats: [CharacterProgress.Axis: Int], stage: CharacterProgress.Stage) -> CharacterAppearance {
        func value(_ axis: CharacterProgress.Axis) -> Double {
            let raw = Double(stats[axis] ?? 0)
            guard raw.isFinite else { return 0 }
            return min(1, max(0, raw / 99))
        }
        let stageBoost = Double(stage.rawValue) / Double(max(1, CharacterProgress.Stage.allCases.count - 1))
        return CharacterAppearance(
            shoulder: 0.35 + 0.65 * value(.push),
            arm: 0.30 + 0.70 * value(.arms),
            leg: 0.30 + 0.70 * value(.legs),
            torso: 0.35 + 0.65 * max(value(.core), value(.pull)),
            aura: stageBoost
        )
    }
}

/// キャラの配色テーマ（スキン）。強さには一切関係しない見た目だけの要素で、課金の対象はここに限る。
struct CharacterSkin: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// 体の主色（16進）。
    let bodyHex: UInt
    /// 差し色（ウェア）。
    let accentHex: UInt
    /// 有料かどうか（無料スキンは最初から所持）。
    let isPaid: Bool
    /// 表示価格。課金は未接続のダミーなので表示専用。
    let priceLabel: String
}

/// スキンのカタログ。
enum SkinCatalog {
    static let defaultSkinId = "classic"

    static let all: [CharacterSkin] = [
        CharacterSkin(id: "classic", name: "クラシック", bodyHex: 0xE8B48A, accentHex: 0x3A4038, isPaid: false, priceLabel: "所持済み"),
        CharacterSkin(id: "midnight", name: "ミッドナイト", bodyHex: 0x8FA0C8, accentHex: 0x1E2333, isPaid: true, priceLabel: "¥370"),
        CharacterSkin(id: "sunset", name: "サンセット", bodyHex: 0xF2A65A, accentHex: 0x8C3B2E, isPaid: true, priceLabel: "¥370"),
        CharacterSkin(id: "gymnee", name: "Gymnee ライム", bodyHex: 0xC6FF3D, accentHex: 0x2F3A1B, isPaid: true, priceLabel: "¥610"),
    ]

    static func skin(id: String?) -> CharacterSkin {
        all.first { $0.id == id } ?? all[0]
    }

    /// 所持しているスキン（無料スキンは常に所持）。
    static func isOwned(_ skin: CharacterSkin, purchased: Set<String>) -> Bool {
        !skin.isPaid || purchased.contains(skin.id)
    }
}

/// 装備の着脱ルール。所持していない装備や、存在しない id は弾く（データが壊れても姿が壊れない）。
enum CharacterOutfit {

    /// 部位 → 装備 id の対応。
    typealias Loadout = [Expedition.Slot: String]

    /// 保存された装備から、実際に着られるものだけを取り出す。
    static func resolve(loadout: Loadout, owned: Set<String>) -> [Expedition.Slot: Expedition.Item] {
        var result: [Expedition.Slot: Expedition.Item] = [:]
        for (slot, itemId) in loadout {
            guard owned.contains(itemId), let item = Expedition.item(id: itemId), item.slot == slot else { continue }
            result[slot] = item
        }
        return result
    }

    /// 手持ちのうち、その部位に装備できるもの（レア度の高い順）。
    static func candidates(for slot: Expedition.Slot, owned: Set<String>) -> [Expedition.Item] {
        Expedition.items(in: slot)
            .filter { owned.contains($0.id) }
            .sorted { $0.rarity > $1.rarity }
    }

    /// 新しく手に入れた装備を自動で着せるべきか（同じ部位に何も着けていない、またはより良いものを引いたとき）。
    /// 手動で着替える手間なく「持ち帰ったら姿が変わる」を成立させる。
    static func shouldAutoEquip(_ item: Expedition.Item, current: Expedition.Item?) -> Bool {
        guard let current else { return true }
        return item.rarity > current.rarity
    }
}
