import Foundation

/// 見た目の試着（issue #154）。
///
/// 見た目シートの上の全身プレビューは**着ているもの**しか描かず、買っていない色・髪型・アクセ・ペットは
/// 一覧の小さな見本でしか見られなかった。「着たらどうなるか分からないので買いにくい」という声を受け、
/// 買う前に 1 つだけ試着してプレビューに出せるようにする。試着は保存しない（シートを閉じたら元に戻る）。
struct AppearanceTryOn: Equatable, Sendable {
    var skinId: String
    var hairId: String
    var accessoryId: String
    var petId: String

    /// 試着しているもの（種別と id）。
    struct Trial: Equatable, Sendable {
        let kind: StoreCatalog.Kind
        let id: String
    }

    /// 着ているものに試着を重ねた見た目。試着が無ければ着ているもののまま。
    func applying(_ trial: Trial?) -> AppearanceTryOn {
        guard let trial else { return self }
        var result = self
        switch trial.kind {
        case .skin: result.skinId = trial.id
        case .hair: result.hairId = trial.id
        case .accessory: result.accessoryId = trial.id
        case .pet: result.petId = trial.id
        }
        return result
    }

    /// 試着の押し直し。同じものをもう一度押したら試着をやめ、別のものなら差し替える。
    static func toggled(_ current: Trial?, with next: Trial) -> Trial? {
        current == next ? nil : next
    }
}
