import SwiftUI
import SwiftData

/// コーチとのチャット（#79）。自由入力で相談し、返ってきたメニュー提案をその場で取り込める。
///
/// 会話は `CoachMessage` としてローカルに残り、同期でサーバーへ送られる（本人しか読めない）。
/// LLM に繋がらないときも、選択肢式の相談（`CoachConsultation`）に落ちて会話は成立する。
struct CoachChatView: View {
    let userId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env

    @AppStorage(CoachMode.storageKey) private var modeRaw = CoachMode.default.rawValue
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3

    @Query private var messages: [CoachMessage]
    @Query private var workouts: [Workout]
    @Query private var records: [PersonalRecord]
    @Query private var plans: [PlannedWorkout]
    /// 育成の現在値（パワー・レベル）の材料。部屋と同じ式で出すために要る。
    @Query private var pickups: [RoomPickupRecord]
    @Query private var runs: [ExpeditionRun]

    @State private var draft = ""
    @State private var appliedPlanTitle: String?
    /// 今日より前の会話まで遡って表示しているか（既定は畳む）。
    @State private var showsPast = false
    @FocusState private var inputFocused: Bool

    init(userId: UUID) {
        self.userId = userId
        _messages = Query(
            filter: #Predicate<CoachMessage> { $0.userId == userId },
            sort: [SortDescriptor(\CoachMessage.createdAt, order: .forward)]
        )
        _workouts = Query(filter: #Predicate<Workout> { $0.userId == userId && $0.completedAt != nil })
        _records = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId })
        _plans = Query(filter: #Predicate<PlannedWorkout> { $0.userId == userId })
        _pickups = Query(filter: #Predicate<RoomPickupRecord> { $0.userId == userId })
        _runs = Query(filter: #Predicate<ExpeditionRun> { $0.userId == userId })
    }

    private var mode: CoachMode { CoachMode(rawValue: modeRaw) ?? .default }

    /// 今日の残り回数（Gemini のコスト制御。プランによる出し分けはしない）。
    private var remaining: Int {
        CoachQuota.remaining(sentToday: env.coach.sentToday)
    }
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !env.coach.isSending
            && remaining > 0
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        // 既定は今日の相談だけを開く。過去は消さずに畳んでおき、明示的に遡れる。
                        let split = transcript
                        if !split.past.isEmpty {
                            if showsPast {
                                ForEach(split.past) { message in
                                    bubble(message).id(message.id)
                                }
                                todayDivider
                            } else {
                                pastButton(count: split.past.count, proxy: proxy)
                            }
                        }
                        if split.today.isEmpty { emptyState }
                        ForEach(split.today) { message in
                            bubble(message)
                                .id(message.id)
                        }
                        if env.coach.isSending { typingIndicator }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(Theme.Spacing.lg)
                }
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                .onAppear { scrollToBottom(proxy) }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .background(Theme.bg0)
            .navigationTitle(CoachPersona.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
            .alert("計画に入れた", isPresented: Binding(
                get: { appliedPlanTitle != nil },
                set: { if !$0 { appliedPlanTitle = nil } }
            )) {
                Button("わかった") { appliedPlanTitle = nil }
            } message: {
                Text("「\(appliedPlanTitle ?? "")」を今日のクエストにした。記録タブから始められる")
            }
        }
    }

    // MARK: - 会話

    /// 今日ぶんと、それ以前に割った会話。
    private var transcript: CoachTranscript.Split<CoachMessage> {
        CoachTranscript.split(messages) { $0.createdAt }
    }

    /// 過去の相談へ遡る入口。消えてはいないことを件数で示す。
    /// 開いたあとは表示位置を今日の末尾に戻す。上に過去が挿し込まれるぶん、
    /// そのままだと履歴の先頭（一番古い相談）へ飛んでしまい、いた場所を見失う。
    private func pastButton(count: Int, proxy: ScrollViewProxy) -> some View {
        Button {
            showsPast = true
            Task { @MainActor in proxy.scrollTo("bottom", anchor: .bottom) }
        } label: {
            Label("これまでの相談を見る（\(count)件）", systemImage: "clock.arrow.circlepath")
                .font(.caption)
        }
        .buttonStyle(.gymneeSecondary)
        .frame(maxWidth: .infinity)
    }

    /// 遡って表示したときの「ここから今日」の目印。
    private var todayDivider: some View {
        Text("今日")
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xs)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                CoachFace()
                Text(openingLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            }
            // 何を聞けるか分からないと最初の一言が出ないので、入り口を並べておく。
            FlowLayout(spacing: Theme.Spacing.sm) {
                ForEach(CoachConsultation.topics(for: chatterContext)) { topic in
                    Button(topic.question) { send(topic.question) }
                        .buttonStyle(.gymneeSecondary)
                }
            }
        }
    }

    private var openingLine: String {
        CharacterChatter.line(for: chatterContext).text
    }

    @ViewBuilder
    private func bubble(_ message: CoachMessage) -> some View {
        if message.isFromCoach {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    CoachFace()
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    Spacer(minLength: Theme.Spacing.lg)
                }
                if message.hasPendingProposal {
                    proposalCard(message)
                }
            }
        } else {
            HStack {
                Spacer(minLength: Theme.Spacing.xl)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.onLime)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.limeFill, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            }
        }
    }

    /// メニュー提案。**押すまでは何も変わらない**（勝手に計画を書き換えない）。
    private func proposalCard(_ message: CoachMessage) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(proposalLines(message).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Button(mode.decidesMenu ? "これで行く" : "今日のクエストにする") {
                if let plan = env.coach.applyProposal(message, userId: userId, context: context) {
                    appliedPlanTitle = plan.title
                }
            }
            .buttonStyle(.gymneePrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymneeCard(padding: Theme.Spacing.md, highlighted: true)
        .padding(.leading, 44)
    }

    private func proposalLines(_ message: CoachMessage) -> [String] {
        guard let json = message.proposalJSON,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exercises = obj["exercises"] as? [[String: Any]] else { return [] }
        var lines: [String] = []
        if let title = obj["title"] as? String { lines.append(title) }
        for exercise in exercises {
            let name = exercise["name"] as? String ?? "種目"
            let sets = exercise["sets"] as? Int ?? 3
            let reps = exercise["reps"] as? Int ?? 10
            let weight = (exercise["weightKg"] as? Double).map { Int($0.isFinite ? $0.rounded() : 0) }
                ?? (exercise["weightKg"] as? Int) ?? 0
            lines.append(weight > 0 ? "・\(name) \(weight)kg × \(reps) × \(sets)セット" : "・\(name) \(reps)回 × \(sets)セット")
        }
        return lines
    }

    private var typingIndicator: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CoachFace()
            ProgressView().controlSize(.small)
            Spacer()
        }
    }

    // MARK: - 入力

    private var composer: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if remaining <= 0 {
                Text(CoachQuota.limitMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.lg)
            } else if remaining <= 3 {
                Text("今日はあと\(remaining)回話せる")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            HStack(spacing: Theme.Spacing.sm) {
                TextField("相談する（例: 今日は肩が痛い）", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .disabled(remaining <= 0)

                Button {
                    send(draft)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.onLime)
                        .frame(width: 34, height: 34)
                        .background(canSend ? Theme.limeFill : Theme.bg3, in: Circle())
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(.bar)
    }

    // MARK: - 送信

    private func send(_ text: String) {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty, remaining > 0 else { return }
        draft = ""
        inputFocused = false
        let snapshot = messages
        Task {
            await env.coach.send(
                payload,
                userId: userId,
                brief: brief,
                mode: mode,
                history: snapshot,
                context: context
            )
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    // MARK: - 材料

    private var todayPlan: PlannedWorkout? {
        let calendar = Calendar.current
        return plans.first { calendar.isDate($0.date, inSameDayAs: .now) && !$0.isDone }
    }

    private var brief: CoachBrief {
        CoachInputs.brief(
            workouts: workouts,
            records: records,
            weeklyGoal: weeklyGoal,
            streakWeeks: StreakCalculator.currentWeeklyStreak(
                activeDays: workouts.map { $0.completedAt ?? $0.date }, weeklyGoal: weeklyGoal
            ).weeks,
            todayPlan: todayPlan,
            growth: CharacterInputs.growth(
                completedWorkouts: workouts, records: records,
                pickups: pickups, runs: runs, weeklyGoal: weeklyGoal
            )
        )
    }

    /// 選択肢式の入り口と開口一番に使う状況（LLM を呼ばずに作れる範囲）。
    private var chatterContext: CharacterChatter.Context {
        let calendar = Calendar.current
        let activeDays = workouts.map { $0.completedAt ?? $0.date }
        return CharacterChatter.Context(
            recordedToday: activeDays.contains { calendar.isDate($0, inSameDayAs: .now) },
            weeklyDone: activeDays.filter { calendar.isDate($0, equalTo: .now, toGranularity: .weekOfYear) }.count,
            weeklyGoal: weeklyGoal,
            streakWeeks: StreakCalculator.currentWeeklyStreak(activeDays: activeDays, weeklyGoal: weeklyGoal).weeks,
            daysSinceLastWorkout: activeDays.max().map {
                max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: .now)).day ?? 0)
            }
        )
    }
}

/// コーチの顔（ドット絵）。チャットの各発言に添える。
struct CoachFace: View {
    var side: CGFloat = 36

    var body: some View {
        Canvas { context, size in
            let sprite = PixelCharacterArt.coachHead(blinking: false)
            let dot = max(1, (size.width / CGFloat(sprite.width)).rounded(.down))
            let w = CGFloat(sprite.width) * dot
            let h = CGFloat(sprite.height) * dot
            context.drawPixels(
                sprite,
                at: CGPoint(x: ((size.width - w) / 2).rounded(), y: ((size.height - h) / 2).rounded()),
                dot: dot,
                palette: .make(skin: PixelCharacterRenderer.coachSkin)
            )
        }
        .frame(width: side, height: side)
        .background(Theme.bg2, in: Circle())
        .accessibilityHidden(true)
    }
}
