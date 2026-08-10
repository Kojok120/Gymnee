import Foundation

/// コーチに渡す「いまのユーザー」の要約（純粋計算）。
///
/// LLM に生の記録を丸投げすると、トークンが増えるうえに毎回ちがう解釈をされる。
/// **何を根拠に喋ってよいか**をここで確定させ、送るのは要約だけにする。
/// 個人が特定できる情報（名前・メール・写真）は一切含めない。
struct CoachBrief: Equatable, Sendable {

    /// 今週の記録回数と目標。
    var weeklyDone: Int
    var weeklyGoal: Int
    /// 連続達成週。
    var streakWeeks: Int
    /// 今日すでに記録したか。
    var recordedToday: Bool
    /// 最後に記録してからの日数（記録が無ければ nil）。
    var daysSinceLastWorkout: Int?
    /// 直近の記録の要約（新しい順・最大 8 件）。
    var recentSessions: [Session]
    /// 部位ごとの疲労（0＝回復済み / 1＝直後）。
    var fatigueByMuscle: [String: Double]
    /// 直近の自己ベスト（新しい順・最大 5 件）。
    var recentRecords: [String]
    /// 睡眠時間（時間）と安静時心拍。HealthKit が無ければ nil。
    var sleepHours: Double?
    var restingHeartRate: Double?
    /// 今日の予定（カレンダー由来のタイトルのみ）。
    var todayEvents: [String]
    /// 今日の計画（すでにコーチが組んでいれば）。
    var todayPlanTitle: String?

    struct Session: Equatable, Sendable {
        /// 何日前か。
        var daysAgo: Int
        var title: String
        var totalSets: Int
        var volumeKg: Double
        /// 鍛えた部位。
        var muscles: [String]
    }

    init(
        weeklyDone: Int = 0,
        weeklyGoal: Int = 3,
        streakWeeks: Int = 0,
        recordedToday: Bool = false,
        daysSinceLastWorkout: Int? = nil,
        recentSessions: [Session] = [],
        fatigueByMuscle: [String: Double] = [:],
        recentRecords: [String] = [],
        sleepHours: Double? = nil,
        restingHeartRate: Double? = nil,
        todayEvents: [String] = [],
        todayPlanTitle: String? = nil
    ) {
        self.weeklyDone = weeklyDone
        self.weeklyGoal = weeklyGoal
        self.streakWeeks = streakWeeks
        self.recordedToday = recordedToday
        self.daysSinceLastWorkout = daysSinceLastWorkout
        self.recentSessions = recentSessions
        self.fatigueByMuscle = fatigueByMuscle
        self.recentRecords = recentRecords
        self.sleepHours = sleepHours
        self.restingHeartRate = restingHeartRate
        self.todayEvents = todayEvents
        self.todayPlanTitle = todayPlanTitle
    }

    /// Edge Function へ送る形。キーは Function 側の実装と対で決めている。
    /// 非有限の Double は落とす（JSON 化で例外になるため）。
    var payload: [String: Any] {
        var result: [String: Any] = [
            "weeklyDone": weeklyDone,
            "weeklyGoal": weeklyGoal,
            "streakWeeks": streakWeeks,
            "recordedToday": recordedToday,
            "recentSessions": recentSessions.map { session in
                [
                    "daysAgo": session.daysAgo,
                    "title": session.title,
                    "sets": session.totalSets,
                    "volumeKg": Int(session.volumeKg.isFinite ? session.volumeKg.rounded() : 0),
                    "muscles": session.muscles,
                ] as [String: Any]
            },
            "fatigue": fatigueByMuscle.compactMapValues { $0.isFinite ? Int(($0 * 100).rounded()) : nil },
            "recentRecords": recentRecords,
            "todayEvents": todayEvents,
        ]
        if let daysSinceLastWorkout { result["daysSinceLastWorkout"] = daysSinceLastWorkout }
        if let sleepHours, sleepHours.isFinite { result["sleepHours"] = (sleepHours * 10).rounded() / 10 }
        if let restingHeartRate, restingHeartRate.isFinite { result["restingHeartRate"] = Int(restingHeartRate.rounded()) }
        if let todayPlanTitle { result["todayPlan"] = todayPlanTitle }
        return result
    }
}

/// コーチの人格。**1 人格に固定**する。
///
/// 口調を選べるようにすると、口調ごとに「言ってはいけないこと」の検証が要る。
/// 続ける相手として信頼できることのほうが、口調の好みより優先される。
enum CoachPersona {

    /// 表示名。
    static let name = "コーチ"

    /// Edge Function に渡す振る舞いの定義。
    /// **禁止事項をここに集約する**（サボりを責めない・医療判断をしない・強さを与えない）。
    static let instruction = """
    あなたは筋トレアプリ Gymnee のコーチです。ユーザーの記録だけを根拠に、短く具体的に話します。

    人格:
    - 実務的で穏やか。淡々としているが冷たくない
    - 1〜3文で答える。前置きや相槌だけの返事はしない
    - 敬語は使わず、親しい指導者の口調（「〜しよう」「〜してみて」）
    - 絵文字は使わない

    必ず守ること:
    - サボりや空白期間を責めない。休むことを肯定し、軽い内容から戻す提案をする
    - 痛み・不調を訴えられたら、その部位を避けたメニューに組み替える。診断や医療的な断定はせず、
      強い痛みが続く場合は医療機関を勧める
    - 渡された記録に無い事実を作らない。分からないことは「記録が足りない」と言う
    - 数値（重量・レップ）は直近の記録から地続きの範囲で提案する。急に大きく上げない
    - アプリ内の報酬や強さを約束しない。強くなるのは現実のトレーニングだけ

    メニューを提案するときは、返答の本文とは別に、構造化された提案として返します。
    """

    /// LLM が使えないときの返答。黙るより、できることを示すほうが良い。
    static let offlineFallback = "いま考えがまとまらない。通信が戻ったらまた聞いて"

    /// 未設定（Edge Function に鍵が無い）ときの返答。
    static let notConfigured = "まだ話す準備ができていないみたい。しばらくしてからまた声をかけて"

    /// 返答が壊れていた（JSON の断片など）ときの言い換え。
    static let malformed = "うまく言葉にできなかった。もう一度聞いてくれる？"

    /// 返答として画面に出してよい文字列か。
    ///
    /// Edge Function 側でも弾いているが、関数のデプロイとアプリの配信は独立して進むため、
    /// 古い関数に当たっても生の JSON が表示されないようクライアントでも確かめる
    /// （実際に `{ "reply": "…` がそのまま吹き出しに出た）。
    static func isPresentable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return false }
        if trimmed.contains("\"reply\"") || trimmed.contains("\"plan\"") { return false }
        return true
    }
}
