import Foundation

/// 初回ワークアウト用の「はじめてのメニュー」（issue #119）。
///
/// ワークアウトを一度も完了していない人に開始ゲートで選ばせ、選んだメニューを
/// 今日の `PlannedWorkout`（detailJSON）として保存する。記録画面は今日の計画を
/// 先頭タブに重量・レップ入りのカードで並べるので、白紙から種目を探さずに
/// タップだけで最初の1セットを記録できる。
///
/// - 種目名は `SeedData.presetExercises` に実在する名前だけを使う（計画カードは名前で
///   種目を引き、無い名前は黙って落ちるため。テストで網羅チェック）。
/// - 初めての人が迷わず安全に扱えるよう、ジム向けはマシン・ケーブル中心にする。
/// - 重量は `ExerciseDefaults` の初心者向け初期値（無ければ 0＝自重）。
enum StarterMenu {
    struct Item: Equatable, Sendable {
        let name: String
        let muscle: MuscleGroup
        let sets: Int
        let reps: Int
    }

    struct Menu: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let caption: String
        let icon: String
        let items: [Item]
    }

    /// はじめてのメニューから作った計画の目印（`PlannedWorkout.note`）。
    /// 別のメニューを選び直した時に、この目印の付いた未消化の計画だけを置き換える
    /// （ユーザーが自分で入れた今日の計画は消さない）。
    static let planNote = "はじめてのメニュー"

    static let menus: [Menu] = [
        Menu(
            id: "full-body-machine",
            title: "全身をひと通り",
            caption: "マシン中心の5種目",
            icon: "figure.strengthtraining.traditional",
            items: [
                Item(name: "チェストプレス", muscle: .chest, sets: 3, reps: 10),
                Item(name: "ラットプルダウン", muscle: .back, sets: 3, reps: 10),
                Item(name: "レッグプレス", muscle: .legs, sets: 3, reps: 10),
                Item(name: "ショルダープレス", muscle: .shoulders, sets: 3, reps: 10),
                Item(name: "クランチ", muscle: .abs, sets: 3, reps: 15),
            ]
        ),
        Menu(
            id: "upper-body",
            title: "上半身",
            caption: "胸・背中・肩・腕",
            icon: "figure.arms.open",
            items: [
                Item(name: "チェストプレス", muscle: .chest, sets: 3, reps: 10),
                Item(name: "ラットプルダウン", muscle: .back, sets: 3, reps: 10),
                Item(name: "シーテッドロウ", muscle: .back, sets: 3, reps: 10),
                Item(name: "サイドレイズ", muscle: .shoulders, sets: 3, reps: 12),
                Item(name: "ダンベルカール", muscle: .arms, sets: 3, reps: 10),
                Item(name: "トライセプスプレスダウン", muscle: .arms, sets: 3, reps: 10),
            ]
        ),
        Menu(
            id: "lower-body",
            title: "下半身",
            caption: "脚・お尻・お腹",
            icon: "figure.step.training",
            items: [
                Item(name: "レッグプレス", muscle: .legs, sets: 3, reps: 10),
                Item(name: "レッグエクステンション", muscle: .legs, sets: 3, reps: 12),
                Item(name: "レッグカール", muscle: .legs, sets: 3, reps: 12),
                Item(name: "ヒップアブダクション", muscle: .glutes, sets: 3, reps: 12),
                Item(name: "クランチ", muscle: .abs, sets: 3, reps: 15),
            ]
        ),
        Menu(
            id: "home-bodyweight",
            title: "家で器具なし",
            caption: "自重の5種目",
            icon: "house",
            items: [
                Item(name: "腕立て伏せ", muscle: .chest, sets: 3, reps: 10),
                Item(name: "ヒップリフト", muscle: .glutes, sets: 3, reps: 15),
                Item(name: "バックエクステンション", muscle: .back, sets: 3, reps: 12),
                Item(name: "クランチ", muscle: .abs, sets: 3, reps: 15),
                Item(name: "バーピー", muscle: .fullBody, sets: 3, reps: 8),
            ]
        ),
    ]

    /// 開始ゲートに出すかどうか。完了したワークアウトが無い人（＝初回）にだけ出す。
    static func shouldOffer(completedWorkoutCount: Int) -> Bool {
        completedWorkoutCount == 0
    }

    /// 計画の detailJSON（`PlanDetail` 形式）を作る。
    /// 重量は名前で引いた初期値。引けない種目（自重）は 0。
    static func detailJSON(
        for menu: Menu,
        startWeight: (String) -> Double? = { ExerciseDefaults.entry(for: $0)?.startWeight }
    ) -> String? {
        let payload = menu.items.map { item in
            PlanDetail.Exercise(
                name: item.name,
                muscleGroup: item.muscle.rawValue,
                sets: item.sets,
                reps: item.reps,
                weight: startWeight(item.name) ?? 0
            )
        }
        return PlanDetail.encode(payload)
    }
}
