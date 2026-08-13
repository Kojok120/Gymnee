import Foundation

/// 連れて歩けるペットのカタログ（純粋計算）。
///
/// 売るのは見た目だけ。ペットは強さ・進化・ステータス・遠征の結果に一切影響しない。
enum PetCatalog {

    /// 「連れていない」を表す id。買ったあと外せないのは不親切なので、必ず選べるようにする。
    static let noneId = "none"

    struct Pet: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let detail: String
    }

    static let all: [Pet] = [
        Pet(id: "shiba", name: "しばいぬ", detail: "部屋をついて回る。撫でると喜ぶ"),
        Pet(id: "tabby", name: "とらねこ", detail: "少し離れてついてくる。撫でると喜ぶ"),
    ]

    static func pet(id: String?) -> Pet? {
        guard let id, id != noneId else { return nil }
        return all.first { $0.id == id }
    }

    /// 保存された選択から、実際に連れて歩けるものだけを取り出す。
    ///
    /// 返金・失効で所持が消えたら自動で「連れていない」に落ちる。
    /// `CharacterOutfit.resolve(loadout:owned:)` と同じ考え方で、
    /// データが壊れても持っていないものを描かない。
    static func resolve(selected: String?, owned: Set<String>) -> Pet? {
        guard let pet = pet(id: selected), owned.contains(pet.id) else { return nil }
        return pet
    }
}
