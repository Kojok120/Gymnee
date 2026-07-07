import SwiftUI
import SwiftData

/// ワークアウト計画（§6.5）。今後7日間に、Apple/Google カレンダーの予定とワークアウト計画を重ねて表示。
/// 予定を見ながら手動で配置・移動でき、AI計画（Premium）で自動提案も行う（8c）。
struct WeekPlannerView: View {
    let userId: UUID
    /// 計画を「開始」して実記録を作成→ロガーを開く（遷移はルート＝WorkoutHome側に委ねる）。
    var onStart: (Workout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(CalendarService.self) private var calendarService
    @Environment(GoogleCalendarService.self) private var googleCalendar
    @Environment(AuthService.self) private var auth
    @Environment(HealthKitService.self) private var health
    @Environment(LocalSyncEngine.self) private var syncEngine
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal: Int = 3
    @Query private var planned: [PlannedWorkout]
    @Query private var routines: [Routine]
    @Query private var recentWorkouts: [Workout]

    @State private var addDay: PlanDay?
    // 計画追加の下書き選択（保存するまで永続化しない）。
    @State private var planDraftTitle: String?
    @State private var planDraftRoutineId: UUID?
    @State private var aiInfo = false
    @State private var aiRunning = false
    /// カレンダー連携のミニシート（設定と同じ行を共用）。
    @State private var showCalendarLink = false
    /// ゲスト（未サインイン）がAI計画に触れた時のサインイン促しシート。
    @State private var showSignInPrompt = false
    /// AI計画のチャットシート（体調シグナルの確認＋対話での生成/調整）。
    @State private var showAIOptions = false
    @State private var aiInput = ""
    /// 対話履歴（シートを開いている間のセッションスコープ。永続化しない）。
    @State private var aiMessages: [AIChatMessage] = []
    /// ステージング中の AI 計画（「この計画で確定」までカレンダーへ反映しない）。
    /// nil = 未提案 or 確定済み。追加要望のたびに置き換わる。
    @State private var stagedPlan: [SupabaseClient.PlanItem]?
    /// HealthKit から取れた体調シグナル（nil＝データ無し）。シート表示時に取得。
    @State private var aiSleepHours: Double?
    @State private var aiHRV: Double?

    /// AI計画チャットの1メッセージ。assistant は生成/改訂後の計画プレビューを持てる
    /// （シートを閉じずに結果を見ながら対話できるようにする）。
    struct AIChatMessage: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
        var plan: [SupabaseClient.PlanItem]? = nil

        // 内容は不変・追記のみなので identity 比較で十分（onChange のスクロール追従用）。
        static func == (lhs: AIChatMessage, rhs: AIChatMessage) -> Bool { lhs.id == rhs.id }
    }
    /// カレンダー予定のキャッシュ（startOfDay→予定）。body 毎の同期列挙(hang)を避けるため一度だけ取得。
    @State private var eventsByDay: [Date: [CalendarEvent]] = [:]

    init(userId: UUID, onStart: @escaping (Workout) -> Void = { _ in }) {
        self.userId = userId
        self.onStart = onStart
        _planned = Query(filter: #Predicate<PlannedWorkout> { $0.userId == userId }, sort: \PlannedWorkout.date)
        _routines = Query(filter: #Predicate<Routine> { $0.userId == userId }, sort: \Routine.name)
        let since = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        _recentWorkouts = Query(
            filter: #Predicate<Workout> { $0.userId == userId && $0.completedAt != nil && $0.date >= since },
            sort: \Workout.date, order: .reverse
        )
    }

    private struct PlanDay: Identifiable { let date: Date; var id: Double { date.timeIntervalSince1970 } }

    private let cal = Calendar.current
    private var days: [Date] {
        let start = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekPlans: [PlannedWorkout] {
        let set = Set(days.map { cal.startOfDay(for: $0) })
        return planned.filter { set.contains(cal.startOfDay(for: $0.date)) }
    }

    var body: some View {
        List {
            if !weekPlans.isEmpty {
                Section {
                    let done = weekPlans.filter(\.isDone).count
                    let total = weekPlans.count
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack {
                            Text("今週の計画達成").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(done)/\(total)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.lime)
                        }
                        ProgressView(value: Double(done), total: Double(max(total, 1))).tint(Theme.lime)
                    }
                }
            }
            // どのカレンダーとも未連携のときだけ促す（連携済みなら画面に何も足さない）。
            // 連携管理はツールバーのカレンダーアイコンから常時開ける。
            if !calendarLinked {
                Section {
                    Button { showCalendarLink = true } label: {
                        Label("カレンダーと連携", systemImage: "calendar.badge.plus")
                    }
                } footer: {
                    Text("予定を読み込み、空いている日に合わせて計画できます。")
                }
            }
            ForEach(days, id: \.self) { day in
                Section(day.formatted(.dateTime.month().day().weekday(.abbreviated))) {
                    ForEach(events(on: day)) { ev in
                        Label {
                            HStack {
                                Text(ev.title).lineLimit(1)
                                Spacer()
                                Text(ev.isAllDay ? "終日" : ev.start.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: ev.source == .google ? "calendar.circle.fill" : "calendar")
                                .foregroundStyle(ev.source == .google ? Theme.lime : .secondary)
                        }
                    }
                    ForEach(plannedItems(on: day)) { p in
                        plannedRow(p)
                    }
                    Button { addDay = PlanDay(date: day) } label: {
                        Label("ワークアウトを計画", systemImage: "plus.circle").font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("計画")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEvents() }
        .onChange(of: calendarService.authorized) { _, _ in Task { await loadEvents() } }
        .onChange(of: calendarService.isEnabled) { _, _ in Task { await loadEvents() } }
        .onChange(of: googleCalendar.isConnected) { _, _ in Task { await loadEvents() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if aiRunning {
                    ProgressView()
                } else {
                    Button { openAIOptions() } label: { Label("AIで計画", systemImage: "sparkles") }
                }
            }
            // カレンダー連携の管理（設定まで行かずに済む導線。§6.5）。
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCalendarLink = true } label: {
                    Label("カレンダー連携", systemImage: "calendar.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showCalendarLink) { calendarLinkSheet }
        .sheet(item: $addDay) { day in addSheet(day.date) }
        // シートを閉じたら会話ごと破棄する（提案だけでなく履歴も。残すと、その後の手動編集を
        // 無視した古い案が画面に見えたまま、実計画ベースの練り直しと食い違う）。
        .sheet(isPresented: $showAIOptions, onDismiss: resetAIChat) { aiOptionsSheet }
        .sheet(isPresented: $showSignInPrompt) { aiSignInSheet }
        .alert("AIワークアウト計画", isPresented: $aiInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("計画を生成できませんでした。サインイン状態とネットワーク接続を確認して、しばらくおいてからもう一度お試しください。")
        }
    }

    // MARK: - Rows

    private func plannedRow(_ p: PlannedWorkout) -> some View {
        HStack {
            Button {
                p.isDone.toggle(); p.updatedAt = .now; try? context.save()
            } label: {
                Image(systemName: p.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(p.isDone ? Theme.lime : .secondary)
            }
            .buttonStyle(.plain)
            Text(p.title).strikethrough(p.isDone).foregroundStyle(p.isDone ? .secondary : .primary)
            Spacer()
            // 計画の開始は「今日」のみ。過去/未来は閲覧・チェック・移動のみ。
            if cal.isDateInToday(p.date) {
                Button { start(p) } label: {
                    Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(Theme.lime)
                }
                .buttonStyle(.plain)
            }
            Menu {
                Menu("別の日へ移動") {
                    ForEach(days, id: \.self) { d in
                        Button(d.formatted(.dateTime.month().day().weekday(.abbreviated))) {
                            p.date = d; p.updatedAt = .now; try? context.save()
                        }
                    }
                }
                Button("削除", role: .destructive) { context.delete(p); try? context.save() }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Add sheet

    /// 行タップは「選択」のみ。右上「保存」を押すまで永続化しない。
    private func addSheet(_ day: Date) -> some View {
        NavigationStack {
            List {
                Section("カスタムセットから") {
                    if routines.isEmpty {
                        Text("カスタムセットがありません。「カスタムセット」から胸の日などのテンプレで作成すると、計画に使えます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(routines) { r in
                        planSelectRow(title: r.name, routineId: r.id)
                    }
                }
            }
            .navigationTitle(day.formatted(.dateTime.month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { closeAdd() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { savePlan(on: day) }.bold().disabled(planDraftTitle == nil)
                }
            }
            .interactiveDismissDisabled()
        }
        .presentationDetents([.medium, .large])
    }

    /// 計画追加シートの選択行（タップで選択、チェックマーク表示。保存まで永続化しない）。
    @ViewBuilder
    private func planSelectRow(title: String, routineId: UUID?) -> some View {
        let isSelected = planDraftRoutineId == routineId && planDraftTitle == title
        Button {
            planDraftTitle = title
            planDraftRoutineId = routineId
        } label: {
            HStack {
                Text(title).foregroundStyle(Theme.textPrimary)
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(Theme.lime) }
            }
        }
    }

    // MARK: - Helpers

    private func events(on day: Date) -> [CalendarEvent] {
        eventsByDay[cal.startOfDay(for: day)] ?? []
    }

    /// 週分の予定（Apple＋Google）を取得して startOfDay 単位にキャッシュ（body 内の同期列挙を排除）。
    private func loadEvents() async {
        guard let first = days.first, let last = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { eventsByDay = [:]; return }
        var all: [CalendarEvent] = []
        if calendarService.isActive { all += calendarService.calendarEvents(from: first, to: end) }
        if googleCalendar.isConnected { all += await googleCalendar.events(from: first, to: end) }
        eventsByDay = Dictionary(grouping: all) { cal.startOfDay(for: $0.start) }
    }

    private func plannedItems(on day: Date) -> [PlannedWorkout] {
        planned.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    /// 「保存」押下時のみ永続化。下書き選択をクリアしてシートを閉じる。
    private func savePlan(on day: Date) {
        guard let title = planDraftTitle else { return }
        add(title: title, routineId: planDraftRoutineId, on: day)
        planDraftTitle = nil
        planDraftRoutineId = nil
    }

    /// シートを閉じて下書き選択を破棄（保存せず）。
    private func closeAdd() {
        addDay = nil
        planDraftTitle = nil
        planDraftRoutineId = nil
    }

    private func add(title: String, routineId: UUID?, on day: Date) {
        let p = PlannedWorkout(userId: userId, date: day, title: title, routineId: routineId)
        context.insert(p)
        try? context.save()
        addDay = nil
        // 計画作成時に Google カレンダーへ終日予定として自動追加（連携中のみ）。
        if googleCalendar.isConnected {
            let start = cal.startOfDay(for: day)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            Task { await googleCalendar.addEvent(title: "Gymnee: \(title)", start: start, end: end, allDay: true) }
        }
    }

    /// 計画を「開始」：共通ロジックで実記録を作成し（AI詳細→ルーティン→空）ロガーを開く。
    private func start(_ plan: PlannedWorkout) {
        onStart(PlanStarter.start(plan, userId: userId, routines: routines, context: context))
    }

    /// AI計画のサインイン促し（ゲストがAIボタンを押した時。生成はクラウドで行うためサインイン必須）。
    private var aiSignInSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.lime)
                        .padding(.top, 24)
                    Text("AI計画にはサインインが必要です")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text("週の計画づくりはクラウドのAIが生成します。サインインすると初回は無料で試せます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    BackendSignInButtons()
                        .padding(.top, Theme.Spacing.sm)
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("AIで計画")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { showSignInPrompt = false } }
            }
        }
        .presentationDetents([.medium])
        // サインインが成立したらこのシートを閉じる（そのままAIチャットを開けるように）。
        .onChange(of: auth.isBackendAuthenticated) { _, authed in
            if authed { showSignInPrompt = false }
        }
    }

    /// いずれかのカレンダーと連携済みか（Apple はアプリ内トグルまで含めて有効判定）。
    private var calendarLinked: Bool {
        (calendarService.authorized && calendarService.isEnabled) || googleCalendar.isConnected
    }

    /// カレンダー連携のミニシート（設定画面と同じ行を共用。連携/解除の変更は
    /// 既存の onChange(authorized/isEnabled/isConnected) が拾って予定を再読込する）。
    private var calendarLinkSheet: some View {
        NavigationStack {
            Form {
                Section {
                    CalendarLinkRows()
                } footer: {
                    Text("予定を週プランナーに重ねて表示し、計画作成時に Google カレンダーへ自動で予定を追加します。")
                }
            }
            .navigationTitle("カレンダー連携")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { showCalendarLink = false } }
            }
        }
        .presentationDetents([.medium])
    }

    /// AI計画のオプションシートを開く（Paywall 判定は生成時に行う）。
    /// ゲスト（未サインイン）はここがサインイン要求ポイント（AI生成はバックエンド必須のため）。
    /// 体調シグナル（昨夜の睡眠・HRV）は開いた時点で取得して表示する。
    /// HealthKit のクエリは許諾プロンプトを出さないため、先に read 許可（睡眠/HRV含む）を要求する
    /// （許諾済みタイプはスキップされ、非対応端末では no-op）。非有限値はここで弾く。
    private func openAIOptions() {
        if syncEngine.isRemoteEnabled && !auth.isBackendAuthenticated {
            showSignInPrompt = true
            return
        }
        showAIOptions = true
        Task {
            await health.requestAuthorization()
            aiSleepHours = (await health.lastNightSleepHours()).flatMap { $0.isFinite ? $0 : nil }
            aiHRV = (await health.recentHRV()).flatMap { $0.isFinite ? $0 : nil }
        }
    }

    private var aiOptionsSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conditionBanner
                aiChatList
                aiInputBar
            }
            .navigationTitle("AIで計画")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { showAIOptions = false } }
            }
        }
        .presentationDetents([.large])
    }

    /// 体調シグナルの1行バナー（取れた項目のみ）。
    @ViewBuilder private var conditionBanner: some View {
        if aiSleepHours != nil || aiHRV != nil {
            HStack(spacing: Theme.Spacing.md) {
                if let sleep = aiSleepHours {
                    Label("睡眠 \(String(format: "%.1f", sleep))h", systemImage: "moon.zzz.fill")
                }
                if let hrv = aiHRV {
                    Label("HRV \(Int(hrv))ms", systemImage: "waveform.path.ecg")
                }
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, Theme.Spacing.sm)
            .background(Theme.bg1)
        }
    }

    private var aiChatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if aiMessages.isEmpty {
                        VStack(spacing: Theme.Spacing.md) {
                            Text("今週の計画を対話で作成・調整できます。\n体調（睡眠・HRV）と部位の回復状況も反映されます。\n計画は「確定」を押すまでカレンダーに反映されません。")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                sendChat("今週の計画を作って")
                            } label: {
                                Label("今週の計画を作成", systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent).prominentLime()
                            Text("例:「肩が痛いので肩は避けて」「水曜は休みにして」「脚を重点的に」")
                                .font(.caption2).foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    ForEach(aiMessages) { msg in
                        chatBubble(msg).id(msg.id)
                    }
                    if aiRunning {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("計画を作成中…").font(.caption).foregroundStyle(.secondary)
                        }
                        .id("running")
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .onChange(of: aiMessages) { _, msgs in
                if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: aiRunning) { _, running in
                if running { withAnimation { proxy.scrollTo("running", anchor: .bottom) } }
            }
        }
    }

    private func chatBubble(_ msg: AIChatMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(msg.text)
                    .font(.subheadline)
                if let plan = msg.plan {
                    planPreview(plan)
                    // 最新の提案にだけ確定導線を出す（過去の案は表示のみ）。
                    if stagedPlan != nil, msg.id == latestPlanMessageId {
                        Button {
                            confirmStagedPlan()
                        } label: {
                            Label("この計画で確定", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).prominentLime()
                        // 練り直しの応答待ち中は確定不可（確定直後に新提案が届いて食い違うのを防ぐ）。
                        .disabled(aiRunning)
                        Text("確定するまでカレンダーには反映されません。要望を送って練り直せます。")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
            .background(
                msg.role == .user ? Theme.lime.opacity(0.18) : Theme.bg2,
                in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            )
            if msg.role == .assistant { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
    }

    /// 生成/改訂された週計画のプレビュー（チャット内でそのまま結果を見て対話を続けられる）。
    private func planPreview(_ items: [SupabaseClient.PlanItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Divider()
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(Self.planDayLabel(item.date))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        Text(item.exercises.isEmpty ? "休養" : item.title)
                            .font(.caption.weight(item.exercises.isEmpty ? .regular : .semibold))
                            .foregroundStyle(item.exercises.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                            .lineLimit(1)
                    }
                    if !item.exercises.isEmpty {
                        Text(item.exercises.map { ex in
                            let w = ex.weight > 0 ? " \(SetFormatting.weightString(ex.weight))kg" : ""
                            return "\(ex.name) \(ex.sets)×\(ex.reps)\(w)"
                        }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    /// "yyyy-MM-dd" → "M/d(曜)"。パース不能ならそのまま返す。
    private static func planDayLabel(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "ja_JP")
        out.dateFormat = "M/d(E)"
        return out.string(from: date)
    }

    private var aiInputBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("要望を送る（例: 水曜は休みに）", text: $aiInput, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .disabled(aiRunning)
            Button {
                sendChat(aiInput)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(aiRunning || aiInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.bg1)
    }

    /// チャット送信 → AI 生成/改訂を実行。
    private func sendChat(_ text: String) {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !trimmed.isEmpty, !aiRunning else { return }
        aiMessages.append(AIChatMessage(role: .user, text: trimmed))
        aiInput = ""
        runAIPlan()
    }

    private func runAIPlan() {
        aiRunning = true
        Task {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.calendar = cal
            fmt.locale = Locale(identifier: "en_US_POSIX")
            let dayStrings = days.map { fmt.string(from: $0) }
            let routineNames = routines.map(\.name)
            let evs: [[String: Any]] = days.flatMap { d in
                events(on: d).map { ev in
                    ["title": ev.title, "date": fmt.string(from: ev.start), "allDay": ev.isAllDay]
                }
            }
            let history = buildHistory(formatter: fmt)
            let recovery = buildRecovery()
            // 体調シグナル（取れた項目のみ渡す。無ければ空＝従来どおり）。
            var condition: [String: Any] = [:]
            if let sleep = aiSleepHours { condition["sleepHours"] = (sleep * 10).rounded() / 10 }
            if let hrv = aiHRV { condition["hrvMs"] = Int(hrv) }
            let messages = aiMessages.suffix(10).map { ["role": $0.role == .user ? "user" : "assistant", "text": $0.text] }
            let result = await auth.planWorkouts(
                days: dayStrings, routines: routineNames, weeklyGoal: weeklyGoal,
                events: evs, history: history, recovery: recovery,
                condition: condition, messages: Array(messages), currentPlan: currentPlanPayload(formatter: fmt)
            )
            aiRunning = false
            // シートを閉じた（＝会話を破棄した）後に届いた遅延応答は捨てる。
            // 破棄済みの提案が復活し、確定時に手動編集を上書きするのを防ぐ。
            guard showAIOptions else { return }
            if let result, !result.items.isEmpty {
                // 即時反映せずステージング（「この計画で確定」で初めてカレンダーへ書き込む）。
                let sorted = result.items.sorted { $0.date < $1.date }
                stagedPlan = sorted
                let trained = sorted.filter { !$0.exercises.isEmpty }.count
                aiMessages.append(AIChatMessage(
                    role: .assistant,
                    text: result.message ?? "計画案です（トレーニング\(trained)日）。",
                    plan: sorted
                ))
            } else if aiMessages.count <= 1 {
                aiInfo = true   // 初回失敗はキー未設定の可能性 →「準備中」案内
            } else {
                aiMessages.append(AIChatMessage(role: .assistant, text: "うまく更新できませんでした。数秒おいてもう一度送ってください。"))
            }
        }
    }

    /// 直近の提案メッセージ（確定ボタンを付ける対象）。
    private var latestPlanMessageId: UUID? {
        aiMessages.last { $0.plan != nil }?.id
    }

    /// AIチャットの状態を破棄する（シートを閉じる＝会話の終了。次回はまっさらから）。
    private func resetAIChat() {
        stagedPlan = nil
        aiMessages = []
        aiInput = ""
    }

    /// ステージング中の計画を確定＝カレンダーへ反映する。
    private func confirmStagedPlan() {
        guard let staged = stagedPlan else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = cal
        fmt.locale = Locale(identifier: "en_US_POSIX")
        applyPlan(staged, formatter: fmt)
        stagedPlan = nil
        aiMessages.append(AIChatMessage(role: .assistant, text: "計画を確定しました。カレンダーと記録タブの「計画」モードに反映されています。"))
    }

    /// AI の改訂ベースとして渡す現在計画。ステージング中はその案を優先し、
    /// 無ければ確定済みの週計画を渡す（対話の続きが常に最新案の練り直しになる）。
    private func currentPlanPayload(formatter: DateFormatter) -> [[String: Any]] {
        if let staged = stagedPlan {
            return staged.map { item in
                ["date": item.date, "title": item.title,
                 "exercises": item.exercises.map { ["name": $0.name, "sets": $0.sets, "reps": $0.reps, "weight": $0.weight] }]
            }
        }
        return weekPlans.map { p in
            var d: [String: Any] = ["date": formatter.string(from: p.date), "title": p.title, "done": p.isDone]
            if let json = p.detailJSON, let data = json.data(using: .utf8),
               let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                d["exercises"] = arr
            }
            return d
        }
    }

    /// AI が返した計画で、今週分の計画を置き換える。
    private func applyPlan(_ items: [SupabaseClient.PlanItem], formatter: DateFormatter) {
        for p in planned where days.contains(where: { cal.isDate($0, inSameDayAs: p.date) }) {
            context.delete(p)
        }
        for item in items {
            guard let date = formatter.date(from: item.date),
                  days.contains(where: { cal.isDate($0, inSameDayAs: date) }) else { continue }
            let plan = PlannedWorkout(userId: userId, date: cal.startOfDay(for: date), title: item.title)
            if !item.exercises.isEmpty, let data = try? JSONEncoder().encode(item.exercises) {
                plan.detailJSON = String(data: data, encoding: .utf8)
            }
            context.insert(plan)
        }
        try? context.save()
    }

    /// 部位ごとの回復状況を AI 用に要約（RecoveryAnalyzer）。連日同部位を避ける根拠にする。
    private func buildRecovery() -> [[String: Any]] {
        var lastTrained: [MuscleGroup: Date] = [:]
        for w in recentWorkouts where w.completedAt != nil {
            for we in w.exercises where !we.sets.isEmpty {
                guard let mg = we.exercise?.muscleGroup else { continue }
                let d = w.completedAt ?? w.date
                if let e = lastTrained[mg] { lastTrained[mg] = max(e, d) } else { lastTrained[mg] = d }
            }
        }
        return RecoveryAnalyzer.statuses(lastTrained: lastTrained).map { s in
            ["muscle": s.muscle.rawValue,
             "hoursSince": Int(s.hoursSince ?? 9999),
             "recovered": s.isRecovered]
        }
    }

    /// 直近4週間の記録を AI 用に要約（種目・部位・トップセットの重量/レップ）。
    private func buildHistory(formatter: DateFormatter) -> [[String: Any]] {
        recentWorkouts.prefix(20).map { w in
            [
                "date": formatter.string(from: w.date),
                "exercises": w.exercises.compactMap { we -> [String: Any]? in
                    guard let ex = we.exercise else { return nil }
                    let top = we.sets.max(by: { $0.weight < $1.weight })
                    return ["name": ex.name, "muscleGroup": ex.muscleGroupRaw,
                            "weight": top?.weight ?? 0, "reps": top?.reps ?? 0]
                },
            ]
        }
    }
}
