import Foundation
import SwiftData

/// スタータルーティンのテンプレ（§6.5 深掘り）。種目名でプリセットマスタを引いて構成する。
enum RoutineTemplates {
    struct Template: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let sets: Int
        let exerciseNames: [String]
    }

    static let all: [Template] = [
        .init(name: "5x5 ストレングス A", detail: "スクワット/ベンチ/ロウ", sets: 5,
              exerciseNames: ["スクワット", "ベンチプレス", "ベントオーバーロウ"]),
        .init(name: "5x5 ストレングス B", detail: "スクワット/ショルダー/デッド", sets: 5,
              exerciseNames: ["スクワット", "ショルダープレス", "デッドリフト"]),
        .init(name: "PPL プッシュ", detail: "胸・肩・三頭", sets: 4,
              exerciseNames: ["ベンチプレス", "インクラインベンチプレス", "ショルダープレス", "サイドレイズ", "トライセプスプレスダウン"]),
        .init(name: "PPL プル", detail: "背中・二頭", sets: 4,
              exerciseNames: ["デッドリフト", "懸垂", "ベントオーバーロウ", "ラットプルダウン", "バーベルカール"]),
        .init(name: "PPL レッグ", detail: "脚・臀部", sets: 4,
              exerciseNames: ["スクワット", "レッグプレス", "ルーマニアンデッドリフト", "レッグカール", "カーフレイズ"]),
        .init(name: "全身（初心者）", detail: "週2-3向け", sets: 3,
              exerciseNames: ["スクワット", "ベンチプレス", "ラットプルダウン", "ショルダープレス", "プランク"]),
    ]

    /// テンプレから Routine を生成して返す。
    @MainActor
    static func create(_ template: Template, userId: UUID, context: ModelContext) -> Routine {
        let routine = Routine(userId: userId, name: template.name)
        context.insert(routine)
        for (i, name) in template.exerciseNames.enumerated() {
            guard let ex = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })))?.first else { continue }
            let re = RoutineExercise(orderIndex: i, targetSets: template.sets, restSeconds: 90, routine: routine, exercise: ex)
            context.insert(re)
        }
        try? context.save()
        return routine
    }
}
