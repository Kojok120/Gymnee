import Foundation

/// 自分のキャラの見た目の控え（issue #155）。
///
/// 見た目は育成タブが記録・所持・装備から解決していて、ほかの画面からは組み立て直せない。
/// 育成タブが解決するたびにここへ書き、記録画面の戦闘の帯が読む（パーティに載せる形 `MemberLook` のまま持つ）。
/// まだ育成タブを開いていなければ、はじめの姿で描く。
enum CharacterLookStore {
    static let key = "gymnee.character.look"

    static func save(_ look: PartyBoss.MemberLook, defaults: UserDefaults = .standard) {
        defaults.set(look.json, forKey: key)
    }

    static func load(defaults: UserDefaults = .standard) -> PartyBoss.MemberLook {
        PartyBoss.MemberLook(json: defaults.dictionary(forKey: key)) ?? starter
    }

    /// はじめの姿（記録が無い人の見た目）。
    static let starter = PartyBoss.MemberLook(
        build: CharacterBuild(girth: .slim, arm: .thin, leg: .thin),
        skinId: SkinCatalog.defaultSkinId,
        stage: .rookie,
        hairStyleId: PixelHairArt.defaultStyleId,
        accessoryId: "none",
        equipped: [:]
    )
}
