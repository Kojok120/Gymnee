import SwiftUI

/// 共有カード編集（§6.6）。テーマ・表示項目を選び、ネイティブ共有シートで共有。特定SNS API非依存。
struct ShareCardEditorView: View {
    @State var content: ShareCardContent
    @Environment(\.dismiss) private var dismiss

    @State private var theme: ShareCardTheme = .energy
    @State private var rendered: UIImage?
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    ShareCardView(content: content, theme: theme, side: 320)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                        .shadow(radius: 8)

                    themePicker
                    itemToggles
                    actions
                }
                .padding(Theme.Spacing.lg)
            }
            .navigationTitle("共有カード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
            }
            .onAppear(perform: rerender)
            .onChange(of: theme) { _, _ in rerender() }
            .onChange(of: content.showGym) { _, _ in rerender() }
            .onChange(of: content.showStreak) { _, _ in rerender() }
            .onChange(of: content.showPR) { _, _ in rerender() }
            .onChange(of: content.showExercises) { _, _ in rerender() }
            .alert(saveMessage ?? "", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "テーマ")
            Picker("テーマ", selection: $theme) {
                ForEach(ShareCardTheme.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var itemToggles: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "表示項目")
            if content.gymName != nil { Toggle("ジム名", isOn: $content.showGym) }
            if content.streak != nil { Toggle("連続日数", isOn: $content.showStreak) }
            if content.prText != nil { Toggle("PR", isOn: $content.showPR) }
            if content.exerciseSummary != nil || !content.exerciseLines.isEmpty {
                Toggle("種目", isOn: $content.showExercises)
            }
        }
        .tint(Theme.energy)
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let rendered {
                ShareLink(item: Image(uiImage: rendered), preview: SharePreview("Gymnee", image: Image(uiImage: rendered))) {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .prominentLime()

                // ストーリーズ直接共有（Meta App ID 設定済み＋Instagram インストール時のみ表示）。
                // 9:16 のブランド背景に載せた画像を渡す。
                if InstagramSharing.isAvailable {
                    Button {
                        if let story = ShareCardRenderer.renderStory(content: content, theme: theme) {
                            InstagramSharing.shareToStories(background: story)
                        } else {
                            saveMessage = "画像の生成に失敗しました"
                        }
                    } label: {
                        Label("Instagramストーリーズ", systemImage: "camera.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    UIImageWriteToSavedPhotosAlbum(rendered, nil, nil, nil)
                    saveMessage = "写真に保存しました"
                } label: {
                    Label("写真に保存", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                ProgressView()
            }
        }
    }

    private func rerender() {
        rendered = ShareCardRenderer.render(content: content, theme: theme)
    }
}

extension ShareCardContent {
    /// 完了ワークアウトからカード内容を構築する（完了画面の共有導線）。
    @MainActor
    static func from(workout: Workout, streak: Int?) -> ShareCardContent {
        let sets = workout.exercises.flatMap(\.sets)
        let vol = sets.reduce(0.0) { $0 + $1.volume }
        let totalVolume = vol.isFinite ? Int(vol) : 0
        let prCount = workout.exercises
            .compactMap(\.exercise)
            .flatMap(\.personalRecords)
            .filter { $0.workoutId == workout.id }
            .count

        // メニュー一覧：種目ごとに代表セット（最重量→最多reps→最長時間）＋セット数を1行に。
        let lines = workout.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { we -> ShareCardExerciseLine? in
                guard let name = we.exercise?.name,
                      let best = we.sets.max(by: { a, b in
                          if a.weight != b.weight { return a.weight < b.weight }
                          if a.reps != b.reps { return a.reps < b.reps }
                          return (a.durationSeconds ?? 0) < (b.durationSeconds ?? 0)
                      })
                else { return nil }
                return ShareCardExerciseLine(
                    name: name,
                    detail: "\(best.detailText)・\(we.sets.count)セット",
                    isPR: we.sets.contains(where: \.isPR)
                )
            }

        // スタット行：値が無い項目（自重のみの総量0、時間未計測）は載せない。
        var stats: [ShareCardStat] = []
        if totalVolume > 0 { stats.append(ShareCardStat(value: "\(totalVolume.formatted())kg", label: "総量")) }
        if !sets.isEmpty { stats.append(ShareCardStat(value: "\(sets.count)", label: "セット")) }
        if let secs = workout.durationSeconds, secs > 0 {
            stats.append(ShareCardStat(value: "\(max(1, secs / 60))分", label: "時間"))
        }

        return ShareCardContent(
            image: nil,
            date: workout.completedAt ?? workout.date,
            gymName: nil,
            streak: streak,
            prText: prCount > 0 ? "PR \(prCount)" : nil,
            exerciseSummary: "\(workout.name)・\(workout.exercises.count)種目・\(totalVolume)kg",
            exerciseLines: lines,
            stats: stats
        )
    }

    /// 来店からカード内容を構築する。
    @MainActor
    static func from(visit: Visit, streak: Int?, prText: String?) -> ShareCardContent {
        ShareCardContent(
            image: PhotoStore.load(visit.localPhotoFilename),
            date: visit.visitedAt,
            gymName: visit.gym?.name,
            streak: streak,
            prText: prText,
            exerciseSummary: visit.workouts.first.map { "\($0.exercises.count)種目を記録" }
        )
    }
}
