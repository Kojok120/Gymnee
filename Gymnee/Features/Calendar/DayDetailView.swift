import SwiftUI
import SwiftData

/// 日別詳細（§5 Day Detail）。その日の計画・来店・ワークアウト一覧。
struct DayDetailView: View {
    let userId: UUID
    let date: Date
    /// ワークアウト編集を開く。pushed view 上では navigationDestination が無効(iOS26.5)なため、
    /// ロガーへの遷移はルート(CalendarHomeContent)側に委ねる。
    var onEditWorkout: (Workout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(GoogleCalendarService.self) private var googleCalendar
    @Query private var visits: [Visit]
    @Query private var workouts: [Workout]
    @Query private var planned: [PlannedWorkout]
    @Query private var routines: [Routine]
    @State private var showAddVisit = false
    @State private var showAddPlan = false
    // 計画追加の下書き選択（保存するまで永続化しない）。
    @State private var planDraftTitle: String?
    @State private var planDraftRoutineId: UUID?

    private let calendar = Calendar.current

    /// 過去日（計画追加の可否に使う。今日・未来で計画追加可）。
    private var isPast: Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: .now)
    }
    /// 未来日（来店/ワークアウト追加の可否に使う。過去・今日で追加可）。
    private var isFuture: Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: .now)
    }

    init(userId: UUID, date: Date, onEditWorkout: @escaping (Workout) -> Void = { _ in }) {
        self.userId = userId
        self.date = date
        self.onEditWorkout = onEditWorkout
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _visits = Query(
            filter: #Predicate<Visit> { $0.userId == userId && $0.visitedAt >= start && $0.visitedAt < end },
            sort: \Visit.visitedAt, order: .reverse
        )
        _workouts = Query(
            // 完了したワークアウトのみ（進行中の下書きは記録扱いしない）。
            filter: #Predicate<Workout> { $0.userId == userId && $0.date >= start && $0.date < end && $0.completedAt != nil },
            sort: \Workout.date, order: .reverse
        )
        _planned = Query(
            filter: #Predicate<PlannedWorkout> { $0.userId == userId && !$0.isDone && $0.date >= start && $0.date < end },
            sort: \PlannedWorkout.date
        )
        _routines = Query(filter: #Predicate<Routine> { $0.userId == userId }, sort: \Routine.name)
    }

    var body: some View {
        List {
            if !planned.isEmpty || !isPast {
                Section("計画") {
                    ForEach(planned) { plan in
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(Theme.lime)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.title).font(.subheadline.weight(.semibold))
                                    .lineLimit(1).truncationMode(.tail)
                                if let n = planExerciseCount(plan) {
                                    Text("\(n)種目").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            // 計画の開始は「今日」のみ。過去/未来は閲覧・削除のみ。
                            if calendar.isDateInToday(date) {
                                Button("開始") { startPlan(plan) }
                                    .buttonStyle(.borderedProminent).prominentLime().controlSize(.small)
                            }
                        }
                        .swipeActions {
                            Button("削除", role: .destructive) { deletePlan(plan) }
                        }
                    }
                    // 計画の追加は「今日・未来」のみ（過去日には不要）。
                    if !isPast {
                        Button { showAddPlan = true } label: {
                            Label("この日に計画を追加", systemImage: "plus.circle")
                        }
                    }
                }
            }

            Section("来店") {
                if visits.isEmpty {
                    Text("来店記録なし").foregroundStyle(.secondary)
                } else {
                    ForEach(visits) { visit in
                        VisitRow(visit: visit)
                            .swipeActions {
                                Button("削除", role: .destructive) { delete(visit) }
                            }
                    }
                }
                // 来店の追加は「未来日」では不可（過去・今日のみ）。
                if !isFuture {
                    Button { showAddVisit = true } label: {
                        Label("この日に来店を追加", systemImage: "plus.circle")
                    }
                }
            }

            Section("ワークアウト") {
                if workouts.isEmpty {
                    Text("ワークアウト記録なし").foregroundStyle(.secondary)
                } else {
                    ForEach(workouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutRow(workout: workout)
                        }
                        .swipeActions {
                            Button("削除", role: .destructive) { deleteWorkout(workout) }
                        }
                    }
                }
                // ワークアウトの追加は「未来日」では不可（過去・今日のみ）。
                if !isFuture {
                    Button { addWorkout() } label: {
                        Label("この日にワークアウトを追加", systemImage: "plus.circle")
                    }
                }
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddVisit) {
            GymPickerView(userId: userId) { gym in
                addVisit(gym: gym)
                showAddVisit = false
            }
        }
        .sheet(isPresented: $showAddPlan) { addPlanSheet }
    }

    /// 計画追加シート（カスタムセットから or 自由入力）。WeekPlannerView の追加シートと同形。
    /// 行タップは「選択」のみ。右上「保存」を押すまで永続化しない。
    private var addPlanSheet: some View {
        NavigationStack {
            List {
                Section("カスタムセットから") {
                    if routines.isEmpty { Text("カスタムセット未作成").foregroundStyle(.secondary) }
                    ForEach(routines) { r in
                        planSelectRow(title: r.name, routineId: r.id)
                    }
                }
                Section("自由入力") {
                    ForEach(["胸の日", "背中の日", "脚の日", "肩・腕", "有酸素", "休養"], id: \.self) { t in
                        planSelectRow(title: t, routineId: nil)
                    }
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { closeAddPlan() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { savePlan() }.bold().disabled(planDraftTitle == nil)
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

    /// その日に来店を追加（ジムを選択して作成）。過去/未来の後追い記録に。
    private func addVisit(gym: Gym) {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let visit = Visit(userId: userId, visitedAt: noon, gym: gym)
        context.insert(visit)
        try? context.save()
        // FK 担保のため参照先ジムも送出してから来店を送る。
        sync.enqueue(PendingChange(entity: "gyms", recordId: gym.id, operation: .upsert, updatedAt: .now))
        sync.enqueue(PendingChange(entity: "visits", recordId: visit.id, operation: .upsert, updatedAt: visit.updatedAt))
    }

    /// その日（過去でも未来でも）にワークアウトを新規作成してロガーを開く。記録の後追い入力・先取り計画に。
    private func addWorkout() {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let workout = Workout(userId: userId, date: noon, name: "ワークアウト")
        context.insert(workout)
        try? context.save()
        onEditWorkout(workout)
    }

    /// 計画を開始＝実記録に変えて記録タブで開く（過去ワークアウトの編集はカレンダー内のまま）。
    private func startPlan(_ plan: PlannedWorkout) {
        let workout = PlanStarter.start(plan, userId: userId, routines: routines, context: context)
        NotificationCenter.default.post(name: .gymneeStartWorkout, object: nil,
                                        userInfo: ["workoutId": workout.id.uuidString])
    }

    private func planExerciseCount(_ plan: PlannedWorkout) -> Int? {
        guard let json = plan.detailJSON, let data = json.data(using: .utf8),
              let exs = try? JSONDecoder().decode([SupabaseClient.PlanExercise].self, from: data), !exs.isEmpty
        else { return nil }
        return exs.count
    }

    /// 「保存」押下時のみ永続化。下書き選択をクリアしてシートを閉じる。
    private func savePlan() {
        guard let title = planDraftTitle else { return }
        addPlan(title: title, routineId: planDraftRoutineId)
        closeAddPlan()
    }

    /// シートを閉じて下書き選択を破棄（保存せず）。
    private func closeAddPlan() {
        showAddPlan = false
        planDraftTitle = nil
        planDraftRoutineId = nil
    }

    /// その日に計画を追加（今日・未来のみ）。PlannedWorkout は端末ローカルのみ（同期対象外）。
    private func addPlan(title: String, routineId: UUID?) {
        let day = calendar.startOfDay(for: date) // plannedDays/クエリは startOfDay 基準
        let plan = PlannedWorkout(userId: userId, date: day, title: title, routineId: routineId)
        context.insert(plan)
        try? context.save()
        // 計画作成時に Google カレンダーへ終日予定として自動追加（連携中のみ）。
        if googleCalendar.isConnected {
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            Task { await googleCalendar.addEvent(title: "Gymnee: \(title)", start: day, end: end, allDay: true) }
        }
    }

    private func deletePlan(_ plan: PlannedWorkout) {
        context.delete(plan) // PlannedWorkout は端末ローカルのみ（同期対象外）
        try? context.save()
    }

    private var titleText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f.string(from: date)
    }

    private func delete(_ visit: Visit) {
        let visitId = visit.id
        PhotoStore.delete(visit.localPhotoFilename)
        context.delete(visit)
        try? context.save()
        sync.enqueue(PendingChange(entity: "visits", recordId: visitId, operation: .delete, updatedAt: .now))
        FeedPublisher.deleteFeedItem(forRefId: visitId, context: context, sync: sync)
    }

    private func deleteWorkout(_ workout: Workout) {
        let id = workout.id
        context.delete(workout) // 配下の workout_exercises / exercise_sets は cascade で削除
        try? context.save()
        sync.enqueue(PendingChange(entity: "workouts", recordId: id, operation: .delete, updatedAt: .now))
        FeedPublisher.deleteFeedItem(forRefId: id, context: context, sync: sync)
    }
}
