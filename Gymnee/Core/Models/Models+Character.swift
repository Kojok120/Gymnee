import Foundation
import SwiftData

/// 遠征の実行記録（ローカル専用モデル）。
///
/// 育成の状態（レベル・進化段階・ステータス・元気）は**すべてワークアウト履歴から導出**するため
/// ここには持たない。非正規化した状態を置くと現実の記録とズレて「現実だけがエンジン」が崩れる。
/// 永続化するのは「いつ・どのコースへ・いくつ元気を払って送り出し、何を受け取ったか」だけ。
///
/// `SwiftDataSyncStore` は同期対象テーブルを明示列挙しているため、このモデルは同期されない
/// （遠征はアプリ内の遊びで、サーバー側に持つ意味がまだ無い）。
@Model
final class ExpeditionRun {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var courseId: String
    var startedAt: Date
    /// 完了予定時刻。コース定義を後から変えても進行中の遠征がぶれないよう実体で持つ。
    var finishesAt: Date
    /// 送り出しに払った元気。手持ちはこの合計を獲得分から引いて求める。
    var energySpent: Int
    /// 報酬の受け取り時刻。nil＝未受取。
    var claimedAt: Date?
    /// 受け取った装備の id（`Expedition.items`）。未受取なら nil。
    var rewardItemId: String?

    init(
        id: UUID = UUID(),
        userId: UUID,
        courseId: String,
        startedAt: Date = .now,
        finishesAt: Date,
        energySpent: Int,
        claimedAt: Date? = nil,
        rewardItemId: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.courseId = courseId
        self.startedAt = startedAt
        self.finishesAt = finishesAt
        self.energySpent = energySpent
        self.claimedAt = claimedAt
        self.rewardItemId = rewardItemId
    }
}

/// キャラの見た目の状態（ローカル専用・ユーザーごとに 1 行）。
///
/// 装備とスキンは見た目だけの情報で、強さ（レベル・進化・ステータス）には一切関与しない。
/// 所持している装備は「受け取り済みの遠征」から導出できるのでここには持たず、
/// 「どれを着ているか」と「どのスキンを買ったか」だけを保存する。
@Model
final class CharacterLoadout {
    @Attribute(.unique) var userId: UUID
    var headItemId: String?
    var handItemId: String?
    var waistItemId: String?
    var auraItemId: String?
    /// 選択中のスキン id（`SkinCatalog`）。
    var skinId: String
    /// 購入済み有料スキンの id（カンマ区切り。課金は未接続のダミー）。
    var purchasedSkinIds: String
    var updatedAt: Date

    init(
        userId: UUID,
        headItemId: String? = nil,
        handItemId: String? = nil,
        waistItemId: String? = nil,
        auraItemId: String? = nil,
        skinId: String = SkinCatalog.defaultSkinId,
        purchasedSkinIds: String = "",
        updatedAt: Date = .now
    ) {
        self.userId = userId
        self.headItemId = headItemId
        self.handItemId = handItemId
        self.waistItemId = waistItemId
        self.auraItemId = auraItemId
        self.skinId = skinId
        self.purchasedSkinIds = purchasedSkinIds
        self.updatedAt = updatedAt
    }
}

extension CharacterLoadout {
    /// 部位 → 装備 id。
    var loadout: CharacterOutfit.Loadout {
        var result: CharacterOutfit.Loadout = [:]
        result[.head] = headItemId
        result[.hand] = handItemId
        result[.waist] = waistItemId
        result[.aura] = auraItemId
        return result.compactMapValues { $0 }
    }

    func setItem(_ itemId: String?, for slot: Expedition.Slot) {
        switch slot {
        case .head: headItemId = itemId
        case .hand: handItemId = itemId
        case .waist: waistItemId = itemId
        case .aura: auraItemId = itemId
        }
        updatedAt = .now
    }

    var purchasedSkins: Set<String> {
        Set(purchasedSkinIds.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    func addPurchasedSkin(_ id: String) {
        var current = purchasedSkins
        current.insert(id)
        purchasedSkinIds = current.sorted().joined(separator: ",")
        updatedAt = .now
    }
}

extension ExpeditionRun {
    var isClaimed: Bool { claimedAt != nil }

    func isFinished(asOf now: Date = .now) -> Bool { now >= finishesAt }

    /// 受け取り待ち＝帰還済みだが未受取。
    func isAwaitingClaim(asOf now: Date = .now) -> Bool { isFinished(asOf: now) && !isClaimed }

    /// 進行中＝まだ帰ってきていない。
    func isInProgress(asOf now: Date = .now) -> Bool { !isFinished(asOf: now) }

    var course: Expedition.Course? { Expedition.course(id: courseId) }

    var reward: Expedition.Item? { rewardItemId.flatMap { Expedition.item(id: $0) } }
}
