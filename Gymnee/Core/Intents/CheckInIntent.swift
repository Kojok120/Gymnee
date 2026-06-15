import AppIntents
import SwiftData
import Foundation

/// 「ジムに着いた」で即チェックイン（§6.10 Siri ショートカット）。
/// お気に入り、なければ最後に訪れたジムへクイックチェックインする。
struct GymCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "ジムに着いた"
    static var description = IntentDescription("お気に入り、または最後に訪れたジムにチェックインします。")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard
            let idString = UserDefaults.standard.string(forKey: "gymnee.auth.userId"),
            let userId = UUID(uuidString: idString)
        else {
            return .result(dialog: "Gymnee にサインインしてください。")
        }

        let container = GymneeSchema.makeContainer()
        let context = container.mainContext

        let gyms = (try? context.fetch(FetchDescriptor<Gym>())) ?? []
        let lastVisit = try? context.fetch(
            FetchDescriptor<Visit>(predicate: #Predicate { $0.userId == userId },
                                   sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
        ).first
        guard let gym = gyms.first(where: { $0.isFavorite }) ?? lastVisit?.gym ?? gyms.first else {
            return .result(dialog: "チェックインできるジムが見つかりませんでした。")
        }

        let visit = Visit(userId: userId, visitedAt: .now, gym: gym)
        context.insert(visit)
        try context.save()
        SnapshotUpdater.update(userId: userId, context: context)

        return .result(dialog: "\(gym.name) にチェックインしました！💪")
    }
}

/// Siri に公開するショートカット定義。
struct GymneeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GymCheckInIntent(),
            phrases: [
                "\(.applicationName)でチェックイン",
                "\(.applicationName)にチェックイン",
                "ジムに着いた\(.applicationName)",
            ],
            shortTitle: "チェックイン",
            systemImageName: "camera.fill"
        )
    }
}
