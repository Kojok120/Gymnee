import Foundation
import SwiftData

/// 初回起動時のプリセット投入（§6.4 ジムマスタ / §6.5 種目マスタ / §6.12 商品）。
/// §9-3（プリセット初期収録範囲）は未確定のため、主要チェーン＋汎用種目の最小セットで開始する。
enum SeedData {
    /// プリセット投入が済んでいなければ投入する。複数回呼んでも安全（冪等）。
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        seedGyms(context)
        migrateMuscleGroups(context)
        seedExercises(context)
        seedProducts(context)
        try? context.save()
    }

    /// 旧部位「二頭(biceps)」「三頭(triceps)」を「二頭・三頭(arms)」へ統合する（既存データ移行）。
    /// 起動ごとに走り、未移行の種目を arms に寄せる。isDirty=true で次回同期時にサーバへも反映される。
    @MainActor
    private static func migrateMuscleGroups(_ context: ModelContext) {
        let legacy = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate {
            $0.muscleGroupRaw == "biceps" || $0.muscleGroupRaw == "triceps"
        }))) ?? []
        guard !legacy.isEmpty else { return }
        for ex in legacy {
            ex.muscleGroupRaw = "arms"
            ex.updatedAt = .now
            ex.isDirty = true
        }
        try? context.save()
    }

    // MARK: - Gyms

    @MainActor
    private static func seedGyms(_ context: ModelContext) {
        let existing = (try? context.fetchCount(
            FetchDescriptor<Gym>(predicate: #Predicate { $0.sourceRaw == "preset" })
        )) ?? 0
        guard existing == 0 else { return }

        for preset in presetGyms {
            let gym = Gym(
                name: preset.name,
                chain: preset.chain,
                source: .preset,
                isDirty: false
            )
            context.insert(gym)
        }
    }

    private struct PresetGym { let name: String; let chain: String }

    /// 主要チェーンの最小セット（自己登録と併用、§6.4）。
    private static let presetGyms: [PresetGym] = [
        .init(name: "エニタイムフィットネス", chain: "Anytime Fitness"),
        .init(name: "ゴールドジム", chain: "Gold's Gym"),
        .init(name: "コナミスポーツクラブ", chain: "Konami Sports"),
        .init(name: "ティップネス", chain: "Tipness"),
        .init(name: "ルネサンス", chain: "Renaissance"),
        .init(name: "セントラルスポーツ", chain: "Central Sports"),
        .init(name: "chocoZAP", chain: "chocoZAP"),
        .init(name: "FASTGYM24", chain: "FASTGYM24"),
        .init(name: "JOYFIT", chain: "JOYFIT"),
        .init(name: "FIT PLACE24", chain: "FitPlace"),
        .init(name: "エクスパンドジム", chain: "Expand"),
    ]

    // MARK: - Exercises

    @MainActor
    private static func seedExercises(_ context: ModelContext) {
        // 同名で二重化したプリセット種目を 1 件に集約する（計測タイプ変更の旧行残存や、別 uid 同期で
        // 入った同名・別 id の古いコピーが原因の重複を自己修復）。参照の付け替え後に削除する。
        dedupePresetExercises(context)
        // 既存プリセットの設定を現行定義に合わせる（部位/器具/計測/重量の数え方/荷重スタイル）。
        reconcilePresets(context)

        // 既存プリセット名を集め、未収録のものだけ追加（名前でべき等）。
        // これで後からプリセットを足しても、DB を消さずに反映される。
        let existingPresets = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isCustom == false })
        )) ?? []
        let existingNames = Set(existingPresets.map { $0.name })

        for preset in presetExercises where !existingNames.contains(preset.name) {
            let exercise = Exercise(
                name: preset.name,
                muscleGroup: preset.muscle,
                equipment: preset.equipment,
                isCustom: false,
                weightMode: preset.weightMode,
                measurementType: preset.measurement,
                loadMode: preset.loadMode,
                isDirty: false
            )
            context.insert(exercise)
        }
    }

    /// 既存プリセット種目の設定を現行定義（presetExercises）へ寄せる（ドメインレビューの反映）。
    /// 部位/器具/計測タイプ/重量の数え方/荷重スタイルを名前一致で補正。ユーザー作成(isCustom)は対象外。
    @MainActor
    private static func reconcilePresets(_ context: ModelContext) {
        let canon = Dictionary(presetExercises.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let existing = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isCustom == false })
        )) ?? []
        var changed = false
        for ex in existing {
            guard let p = canon[ex.name] else { continue }
            var dirty = false
            if ex.muscleGroupRaw != p.muscle.rawValue { ex.muscleGroup = p.muscle; dirty = true }
            if ex.equipmentRaw != p.equipment.rawValue { ex.equipment = p.equipment; dirty = true }
            if ex.measurementTypeRaw != p.measurement.rawValue { ex.measurementType = p.measurement; dirty = true }
            if ex.weightModeRaw != p.weightMode.rawValue { ex.weightMode = p.weightMode; dirty = true }
            if ex.loadModeRaw != p.loadMode.rawValue { ex.loadMode = p.loadMode; dirty = true }
            if dirty { ex.updatedAt = .now; ex.isDirty = true; changed = true }
        }
        if changed { try? context.save() }
    }

    /// 同名で重複したプリセット種目を 1 件に統合する（自己修復）。
    /// 残す 1 件は「現行プリセット定義の計測タイプに一致するもの」を最優先（無ければ参照数が多い→新しい順）。
    /// 残した種目は現行定義（部位/計測タイプ）に合わせて補正し、消す種目の記録/ルーティン参照は残す側へ付け替える。
    @MainActor
    private static func dedupePresetExercises(_ context: ModelContext) {
        let presets = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isCustom == false })
        )) ?? []
        let groups = Dictionary(grouping: presets, by: { $0.name })
        // 名前 → 現行プリセット定義（部位・計測タイプ）。残すべき正準を判定する基準。
        let canonical = Dictionary(presetExercises.map { ($0.name, (muscle: $0.muscle, measure: $0.measurement)) },
                                   uniquingKeysWith: { a, _ in a })

        var changed = false
        for (name, dupes) in groups where dupes.count > 1 {
            let spec = canonical[name]
            let keeper = dupes.sorted { a, b in
                // ① 現行定義の計測タイプに一致する方を優先。
                let aMatch = spec.map { a.measurementType == $0.measure } ?? false
                let bMatch = spec.map { b.measurementType == $0.measure } ?? false
                if aMatch != bMatch { return aMatch }
                // ② 参照（記録・ルーティン）が多い方を残してデータ損失を避ける。
                let aRefs = a.workoutExercises.count + a.routineExercises.count
                let bRefs = b.workoutExercises.count + b.routineExercises.count
                if aRefs != bRefs { return aRefs > bRefs }
                // ③ 新しい方。
                return a.updatedAt > b.updatedAt
            }.first!

            // 残す種目を現行プリセット定義に合わせて補正（古い計測タイプ/部位の行を残した場合の保険）。
            if let spec {
                if keeper.muscleGroup != spec.muscle { keeper.muscleGroup = spec.muscle }
                if keeper.measurementType != spec.measure { keeper.measurementType = spec.measure }
                keeper.updatedAt = .now
                keeper.isDirty = true
            }

            for loser in dupes where loser !== keeper {
                // nullify 関連の参照先削除はエンコード/UI でのアサーション落ちを招くため、先に付け替える。
                // 付け替えた行自体も dirty にしないと、LWW で次回 pull に古い exercise_id が巻き戻る。
                for we in Array(loser.workoutExercises) {
                    we.exercise = keeper
                    we.updatedAt = .now
                    we.isDirty = true
                }
                for re in Array(loser.routineExercises) {
                    re.exercise = keeper
                    re.updatedAt = .now
                    re.isDirty = true
                }
                context.delete(loser)
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// プリセット種目1件の定義（部位/器具/計測タイプ/重量の数え方/自重の荷重スタイル）。
    struct PresetExercise {
        let name: String
        let muscle: MuscleGroup
        let equipment: EquipmentType
        let measurement: MeasurementType
        let weightMode: WeightMode
        let loadMode: LoadMode
    }

    /// 主要種目の最小マスタ（プリセット、§6.5）。各種目の設定はドメインレビュー済み。
    /// weightMode は表示ラベル：ダンベル=片側(perSide) / バーベルで左右合計を入力=両側(both) /
    /// マシン・ケーブル・自重・有酸素・ヒップスラスト等は区別なし(none・ラベル非表示)。
    private static let presetExercises: [PresetExercise] = [
        // 胸
        .init(name: "ベンチプレス", muscle: .chest, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "インクラインベンチプレス", muscle: .chest, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "ダンベルプレス", muscle: .chest, equipment: .dumbbell, measurement: .weight, weightMode: .perSide, loadMode: .none),
        .init(name: "チェストプレス", muscle: .chest, equipment: .machine, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "ペックフライ", muscle: .chest, equipment: .machine, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "スミスマシンベンチプレス", muscle: .chest, equipment: .machine, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "ディップス", muscle: .chest, equipment: .bodyweight, measurement: .bodyweight, weightMode: .none, loadMode: .none),
        // 背中
        .init(name: "デッドリフト", muscle: .back, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "ベントオーバーロウ", muscle: .back, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "ラットプルダウン", muscle: .back, equipment: .cable, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "シーテッドロウ", muscle: .back, equipment: .cable, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "懸垂", muscle: .back, equipment: .bodyweight, measurement: .bodyweight, weightMode: .none, loadMode: .none),
        // 脚
        .init(name: "スクワット", muscle: .legs, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "スミスマシンスクワット", muscle: .legs, equipment: .machine, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "レッグプレス", muscle: .legs, equipment: .machine, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "レッグエクステンション", muscle: .legs, equipment: .machine, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "レッグカール", muscle: .legs, equipment: .machine, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "ルーマニアンデッドリフト", muscle: .legs, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "カーフレイズ", muscle: .legs, equipment: .machine, measurement: .weight, weightMode: .none, loadMode: .none),
        // 肩
        .init(name: "ショルダープレス", muscle: .shoulders, equipment: .dumbbell, measurement: .weight, weightMode: .perSide, loadMode: .none),
        .init(name: "スミスマシンショルダープレス", muscle: .shoulders, equipment: .machine, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "サイドレイズ", muscle: .shoulders, equipment: .dumbbell, measurement: .weight, weightMode: .perSide, loadMode: .none),
        .init(name: "リアレイズ", muscle: .shoulders, equipment: .dumbbell, measurement: .weight, weightMode: .perSide, loadMode: .none),
        .init(name: "アップライトロウ", muscle: .shoulders, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        // 腕
        .init(name: "バーベルカール", muscle: .arms, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        .init(name: "ダンベルカール", muscle: .arms, equipment: .dumbbell, measurement: .weight, weightMode: .perSide, loadMode: .none),
        .init(name: "ハンマーカール", muscle: .arms, equipment: .dumbbell, measurement: .weight, weightMode: .perSide, loadMode: .none),
        .init(name: "トライセプスプレスダウン", muscle: .arms, equipment: .cable, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "スカルクラッシャー", muscle: .arms, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        // 腹
        .init(name: "クランチ", muscle: .abs, equipment: .bodyweight, measurement: .bodyweight, weightMode: .none, loadMode: .none),
        .init(name: "シットアップ", muscle: .abs, equipment: .bodyweight, measurement: .bodyweight, weightMode: .none, loadMode: .none),
        .init(name: "レッグレイズ", muscle: .abs, equipment: .bodyweight, measurement: .bodyweight, weightMode: .none, loadMode: .none),
        .init(name: "ケーブルクランチ", muscle: .abs, equipment: .cable, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "アブローラー", muscle: .abs, equipment: .other, measurement: .bodyweight, weightMode: .none, loadMode: .none),
        // 体幹
        .init(name: "プランク", muscle: .core, equipment: .bodyweight, measurement: .time, weightMode: .none, loadMode: .none),
        // 臀部
        .init(name: "ヒップスラスト", muscle: .glutes, equipment: .barbell, measurement: .weight, weightMode: .none, loadMode: .none),
        // 全身
        .init(name: "バーピー", muscle: .fullBody, equipment: .bodyweight, measurement: .bodyweight, weightMode: .none, loadMode: .none),
        .init(name: "ケトルベルスイング", muscle: .fullBody, equipment: .kettlebell, measurement: .weight, weightMode: .none, loadMode: .none),
        .init(name: "クリーン&ジャーク", muscle: .fullBody, equipment: .barbell, measurement: .weight, weightMode: .both, loadMode: .none),
        // 有酸素（距離km ＋ 時間分）
        .init(name: "ウォーキング", muscle: .cardio, equipment: .other, measurement: .cardio, weightMode: .none, loadMode: .none),
        .init(name: "ランニング", muscle: .cardio, equipment: .other, measurement: .cardio, weightMode: .none, loadMode: .none),
        .init(name: "バイシクル", muscle: .cardio, equipment: .other, measurement: .cardio, weightMode: .none, loadMode: .none),
    ]

    // MARK: - Products

    @MainActor
    private static func seedProducts(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Product>())) ?? 0
        guard existing == 0 else { return }

        for preset in presetProducts {
            let product = Product(
                name: preset.name,
                productDescription: preset.description,
                price: preset.price,
                imageAsset: nil,
                category: preset.category,
                goalTags: preset.goalTags,
                affiliateURL: affiliateURL(for: preset),
                merchant: preset.merchant,
                servingsPerUnit: preset.servings,
                isDirty: false
            )
            context.insert(product)
        }
    }

    private struct PresetProduct {
        let name: String
        let description: String
        let price: Decimal
        let category: String
        let goalTags: [String]
        let servings: Int?
        /// 送客先（"楽天市場" / "iHerb"）。
        let merchant: String
        /// 提携先での検索キーワード（実 ASP タグ付き URL を組み立てる素材）。
        let keyword: String
    }

    /// 楽天アフィリエイトID（計測タグ）。リンク経由の購入で手数料が発生する。
    /// 楽天ウェブサービス ダッシュボードの Affiliate ID と一致させる（送客計上のため）。
    private static let rakutenAffiliateId = "5519c310.d841aa29.5519c311.eac66aa0"

    /// 楽天市場の検索ページを遷移先にし、楽天アフィリエイトの計測リダイレクトで包んだ URL を返す。
    /// （遷移先は `pc=` にフルエンコードして渡す。リモートカタログ＝Supabase products があればそちらが優先。）
    private static func affiliateURL(for preset: PresetProduct) -> String {
        let dest = "https://search.rakuten.co.jp/search/mall/\(preset.keyword)/"
        let encoded = dest.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? dest
        return "https://hb.afl.rakuten.co.jp/hgc/\(rakutenAffiliateId)/?pc=\(encoded)"
    }

    private static let presetProducts: [PresetProduct] = [
        .init(name: "ホエイプロテイン 1kg", description: "高純度ホエイ。増量・維持の基本。", price: 3980, category: "プロテイン", goalTags: ["bulk", "maintain"], servings: 33, merchant: "楽天市場", keyword: "ホエイプロテイン 1kg"),
        .init(name: "ソイプロテイン 1kg", description: "植物性。減量フェーズに。", price: 3580, category: "プロテイン", goalTags: ["cut"], servings: 33, merchant: "楽天市場", keyword: "ソイプロテイン 1kg"),
        .init(name: "クレアチン 500g", description: "高強度トレの定番サプリ。", price: 2480, category: "サプリ", goalTags: ["strength", "bulk"], servings: 100, merchant: "楽天市場", keyword: "クレアチン モノハイドレート"),
        .init(name: "EAA 500g", description: "トレ中のアミノ酸補給。", price: 4280, category: "サプリ", goalTags: ["maintain", "cut"], servings: 50, merchant: "楽天市場", keyword: "EAA アミノ酸"),
        .init(name: "マルトデキストリン 1kg", description: "増量期のカロリー補給に。", price: 1880, category: "カーボ", goalTags: ["bulk"], servings: 20, merchant: "楽天市場", keyword: "マルトデキストリン 1kg"),
        .init(name: "リストラップ", description: "高重量プレス系の手首保護。", price: 1980, category: "ギア", goalTags: ["strength"], servings: nil, merchant: "楽天市場", keyword: "リストラップ 筋トレ"),
        .init(name: "トレーニングベルト", description: "スクワット/デッドの体幹サポート。", price: 5980, category: "ギア", goalTags: ["strength"], servings: nil, merchant: "楽天市場", keyword: "トレーニングベルト"),
        // 減量向け（脂肪代謝・低カロリー・食欲/糖質コントロール）。
        .init(name: "L-カルニチン 1000mg", description: "脂肪をエネルギーに変える代謝サポート。減量期に。", price: 2680, category: "サプリ", goalTags: ["cut"], servings: 60, merchant: "楽天市場", keyword: "L-カルニチン サプリ"),
        .init(name: "CLA 共役リノール酸", description: "体脂肪対策の定番サプリ。減量と併用。", price: 2480, category: "サプリ", goalTags: ["cut"], servings: 90, merchant: "楽天市場", keyword: "CLA 共役リノール酸"),
        .init(name: "難消化性デキストリン 500g", description: "食物繊維。糖の吸収をおだやかに・満腹感。", price: 1280, category: "サプリ", goalTags: ["cut", "maintain"], servings: 50, merchant: "楽天市場", keyword: "難消化性デキストリン"),
        // 維持向け（健康ベース・コンディション）。
        .init(name: "マルチビタミン&ミネラル", description: "不足しがちな微量栄養素の土台。", price: 1980, category: "サプリ", goalTags: ["maintain"], servings: 60, merchant: "楽天市場", keyword: "マルチビタミン ミネラル"),
        .init(name: "フィッシュオイル オメガ3", description: "EPA/DHA。日々のコンディション維持に。", price: 1780, category: "サプリ", goalTags: ["maintain", "cut"], servings: 90, merchant: "楽天市場", keyword: "フィッシュオイル オメガ3 EPA DHA"),
        .init(name: "ビタミンD3", description: "骨・免疫・ホルモンの土台。", price: 980, category: "サプリ", goalTags: ["maintain"], servings: 120, merchant: "楽天市場", keyword: "ビタミンD3 サプリ"),
        // 増量向け（高カロリー・就寝前）。
        .init(name: "ウエイトゲイナー 3kg", description: "高カロリー。食が細い人の増量に。", price: 5480, category: "プロテイン", goalTags: ["bulk"], servings: 30, merchant: "楽天市場", keyword: "ウエイトゲイナー 増量"),
        .init(name: "カゼインプロテイン 1kg", description: "就寝前のゆっくり供給。維持・増量に。", price: 4280, category: "プロテイン", goalTags: ["bulk", "maintain"], servings: 33, merchant: "楽天市場", keyword: "カゼインプロテイン"),
        // 筋力向け（出力・握力補助）。
        .init(name: "ベータアラニン 200g", description: "高強度の粘り。筋力・高レップに。", price: 2280, category: "サプリ", goalTags: ["strength"], servings: 60, merchant: "楽天市場", keyword: "ベータアラニン"),
        .init(name: "パワーグリップ", description: "引く種目の握力補助。背中・デッドに。", price: 2980, category: "ギア", goalTags: ["strength"], servings: nil, merchant: "楽天市場", keyword: "パワーグリップ 筋トレ"),
    ]
}
