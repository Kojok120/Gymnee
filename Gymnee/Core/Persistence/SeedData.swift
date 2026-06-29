import Foundation
import SwiftData

/// 初回起動時のプリセット投入（§6.4 ジムマスタ / §6.5 種目マスタ / §6.12 商品）。
/// §9-3（プリセット初期収録範囲）は未確定のため、主要チェーン＋汎用種目の最小セットで開始する。
enum SeedData {
    /// プリセット投入が済んでいなければ投入する。複数回呼んでも安全（冪等）。
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        seedGyms(context)
        seedExercises(context)
        seedProducts(context)
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

        // 既存プリセット名を集め、未収録のものだけ追加（名前でべき等）。
        // これで後からプリセットを足しても、DB を消さずに反映される。
        let existingPresets = (try? context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isCustom == false })
        )) ?? []
        let existingNames = Set(existingPresets.map { $0.name })

        for preset in presetExercises where !existingNames.contains(preset.0) {
            // 片側/両側の既定は器具で決める（ダンベル/ケトルベル＝片側、他＝両側）。
            let weightMode: WeightMode = (preset.2 == .dumbbell || preset.2 == .kettlebell) ? .perSide : .both
            let exercise = Exercise(
                name: preset.0,
                muscleGroup: preset.1,
                equipment: preset.2,
                isCustom: false,
                weightMode: weightMode,
                measurementType: preset.3,
                isDirty: false
            )
            context.insert(exercise)
        }
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
        let canonical = Dictionary(presetExercises.map { ($0.0, (muscle: $0.1, measure: $0.3)) },
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
                for we in Array(loser.workoutExercises) { we.exercise = keeper }
                for re in Array(loser.routineExercises) { re.exercise = keeper }
                context.delete(loser)
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// 主要種目の最小マスタ（プリセット＋ユーザー作成、§6.5）。
    /// 4要素目は計測タイプ：自重種目は .bodyweight、時間種目は .time、それ以外は .weight。
    private static let presetExercises: [(String, MuscleGroup, EquipmentType, MeasurementType)] = [
        // 胸
        ("ベンチプレス", .chest, .barbell, .weight),
        ("インクラインベンチプレス", .chest, .barbell, .weight),
        ("ダンベルプレス", .chest, .dumbbell, .weight),
        ("チェストプレス", .chest, .machine, .weight),
        ("ペックフライ", .chest, .machine, .weight),
        ("ディップス", .chest, .bodyweight, .bodyweight),
        // 背中
        ("デッドリフト", .back, .barbell, .weight),
        ("ベントオーバーロウ", .back, .barbell, .weight),
        ("ラットプルダウン", .back, .cable, .weight),
        ("シーテッドロウ", .back, .cable, .weight),
        ("懸垂", .back, .bodyweight, .bodyweight),
        // 脚
        ("スクワット", .legs, .barbell, .weight),
        ("レッグプレス", .legs, .machine, .weight),
        ("レッグエクステンション", .legs, .machine, .weight),
        ("レッグカール", .legs, .machine, .weight),
        ("ルーマニアンデッドリフト", .legs, .barbell, .weight),
        ("カーフレイズ", .legs, .machine, .weight),
        // 肩
        ("ショルダープレス", .shoulders, .dumbbell, .weight),
        ("サイドレイズ", .shoulders, .dumbbell, .weight),
        ("リアレイズ", .shoulders, .dumbbell, .weight),
        ("アップライトロウ", .shoulders, .barbell, .weight),
        // 腕
        ("バーベルカール", .biceps, .barbell, .weight),
        ("ダンベルカール", .biceps, .dumbbell, .weight),
        ("ハンマーカール", .biceps, .dumbbell, .weight),
        ("トライセプスプレスダウン", .triceps, .cable, .weight),
        ("スカルクラッシャー", .triceps, .barbell, .weight),
        // 腹
        ("クランチ", .abs, .bodyweight, .bodyweight),
        ("シットアップ", .abs, .bodyweight, .bodyweight),
        ("レッグレイズ", .abs, .bodyweight, .bodyweight),
        ("ケーブルクランチ", .abs, .cable, .weight),
        ("アブローラー", .abs, .other, .bodyweight),
        // 体幹
        ("プランク", .core, .bodyweight, .time),
        // 臀部
        ("ヒップスラスト", .glutes, .barbell, .weight),
        // 全身
        ("バーピー", .fullBody, .bodyweight, .bodyweight),
        ("ケトルベルスイング", .fullBody, .kettlebell, .weight),
        ("クリーン&ジャーク", .fullBody, .barbell, .weight),
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
