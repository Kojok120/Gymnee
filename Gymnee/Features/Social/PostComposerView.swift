import SwiftUI
import SwiftData
import PhotosUI

/// 投稿前ポップアップ（完了サマリー →「ソーシャルに投稿」で開く）。
///
/// ねらいは **「こんな感じで共有されるよ」が一目でわかること**。上半分は飾りのプレビューではなく
/// フィードに出るカードそのもの（`PostCardView(style: .feed)`）で、下で編集した内容が即座に反映される
/// （コメントだけは除く。すぐ下の入力欄と二重になるため）。
/// 投稿先は「アプリ内ソーシャル」と「その他SNS」の 2 つ。押すまでは非公開のまま（fail-closed）。
struct PostComposerView: View {
    let workout: Workout
    /// プレビューに使うフィードエントリ（呼び出し側が FeedBuilder で組んで渡す）。
    let baseEntry: FeedEntry
    /// 投稿完了後に呼ばれる（サマリー側のボタン表示を「投稿しました」に変えるため）。
    var onPosted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(AppErrorCenter.self) private var errors

    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue

    @State private var caption: String = ""
    @State private var visibility: Visibility = .friends
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var posted = false
    @State private var showSharePreview = false
    @FocusState private var captionFocused: Bool

    /// 編集中の内容を反映したエントリ（共有画像の土台）。
    private var previewEntry: FeedEntry {
        var e = baseEntry
        e.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        e.visibility = visibility
        return e
    }

    /// 画面上のプレビューカード用。**コメントはカードに載せない**。
    /// すぐ下の入力欄に同じ文が出ているので、カードにも出すと 1 画面に二重に並ぶだけで、
    /// カード自体の見え方（スタット・PR・写真）の確認を邪魔する。
    private var previewCardEntry: FeedEntry {
        var e = previewEntry
        e.caption = nil
        return e
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    preview
                    presetChips
                    captionField
                    photoButton
                    visibilityPicker
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
            }
            .onAppear {
                // 本文の下書きにワークアウト中メモを流用する（過去に投稿済みなら caption を優先）。
                // メモは投稿前にこの欄で本人が確認・編集できるため、勝手に公開されることはない。
                caption = workout.caption ?? workout.note ?? ""
                visibility = Visibility(rawValue: defaultVisibilityRaw) ?? .friends
                photo = PhotoStore.load(workout.localPhotoFilename)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in attach(image) }
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadPicked(item) }
            }
            .sheet(isPresented: $showSharePreview) {
                SharePreviewSheet(entry: previewEntry, photo: photo)
            }
        }
    }

    // MARK: - プレビュー（実際のフィードカードそのもの）

    private var preview: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            OverlineLabel(text: "こう表示されます")
            PostCardView(entry: previewCardEntry, preloadedPhoto: photo)
        }
    }

    // MARK: - 入力

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(PostCaptionPresets.all) { preset in
                    Button {
                        caption = PostCaptionPresets.appending(preset, to: caption)
                    } label: {
                        Label(preset.label, systemImage: preset.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.bg2, in: Capsule())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            OverlineLabel(text: "コメント")
            TextField("今日はどうだった？", text: $caption, axis: .vertical)
                .lineLimit(3...6)
                .focused($captionFocused)
                .padding(Theme.Spacing.md)
                .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            if caption.count > PostComposerView.captionLimit {
                Text("\(caption.count) / \(PostComposerView.captionLimit) 文字")
                    .font(.caption2).foregroundStyle(Theme.danger)
            }
        }
    }

    private var photoButton: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if CameraPicker.isAvailable {
                Button { showCamera = true } label: {
                    Label("撮影", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(photo == nil ? "写真を追加" : "写真を変更", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.bordered)
            if photo != nil {
                Button(role: .destructive) { removePhoto() } label: {
                    Image(systemName: "trash").frame(width: 24)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var visibilityPicker: some View {
        Picker("公開範囲", selection: $visibility) {
            ForEach(Visibility.allCases, id: \.self) { v in
                Text(v.label).tag(v)
            }
        }
        .pickerStyle(.segmented)
        .disabled(posted)
    }

    // MARK: - アクション

    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                post()
            } label: {
                Label(posted ? "投稿しました" : "ソーシャルに投稿",
                      systemImage: posted ? "checkmark.circle.fill" : "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).prominentLime().controlSize(.large)
            .disabled(posted || !canPost || isOverLimit)

            Button { saveDraftFields(); showSharePreview = true } label: {
                Label("その他SNS", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isOverLimit)

            Text(postFootnote)
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .background(.bar)
    }

    /// アプリ内投稿はバックエンドの恒久アカウントが要る（ゲストは fail-closed で発行しない）。
    private var canPost: Bool { sync.isRemoteEnabled && auth.isPermanentAccount }
    private var isOverLimit: Bool { caption.count > PostComposerView.captionLimit }

    private var postFootnote: String {
        if posted { return "フィードに公開されました。" }
        if !canPost { return "アプリ内ソーシャルへの投稿にはサインインが必要です。画像の共有はそのまま使えます。" }
        return "押さなければ非公開のままです。あとから投稿メニューで公開できます。"
    }

    /// コメントの上限（サーバー側 comments と同じ 500 文字）。
    static let captionLimit = 500

    /// 入力内容をワークアウトへ保存する（投稿しなくても下書きとして残す）。
    private func saveDraftFields() {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCaption = trimmed.isEmpty ? nil : trimmed
        guard workout.caption != newCaption else { return }
        workout.caption = newCaption
        workout.updatedAt = .now
        workout.isDirty = true
        do {
            try context.save()
            sync.enqueue(PendingChange(entity: "workouts", recordId: workout.id, operation: .upsert, updatedAt: workout.updatedAt))
        } catch {
            errors.report(error)
        }
    }

    private func post() {
        saveDraftFields()
        defaultVisibilityRaw = visibility.rawValue
        FeedPublisher.publishWorkout(
            workout,
            authorName: auth.session?.displayName,
            visibility: visibility,
            isPermanentAccount: auth.isPermanentAccount,
            context: context,
            sync: sync
        )
        Task { await sync.syncNow(force: true) }
        withAnimation(.smooth) { posted = true }
        onPosted()
    }

    // MARK: - 写真

    private func loadPicked(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // 高解像度 HEIC をフルデコードすると OOM で落ちるため、必ずダウンサンプルを通す。
        let image = await Task.detached(priority: .userInitiated) { PhotoStore.downsample(data: data) }.value
        guard let image else { return }
        attach(image)
    }

    /// 写真をローカルへ確定し、非同期でストレージへ上げて参照を書き戻す。
    /// 手順は旧チェックインの保存パターンを踏襲: ①ローカル確定 → ②save → ③enqueue → ④アップロード後に
    /// id で再フェッチしてから photoURL を書く（画面破棄後に元オブジェクトを触らない）。
    private func attach(_ image: UIImage) {
        guard let filename = PhotoStore.save(image) else { return }
        PhotoStore.delete(workout.localPhotoFilename)
        workout.localPhotoFilename = filename
        workout.photoURL = nil
        workout.updatedAt = .now
        workout.isDirty = true
        photo = image
        do {
            try context.save()
        } catch {
            errors.report(error)
            return
        }
        sync.enqueue(PendingChange(entity: "workouts", recordId: workout.id, operation: .upsert, updatedAt: workout.updatedAt))
        uploadPhoto(filename: filename, image: image, workoutId: workout.id)
    }

    private func uploadPhoto(filename: String, image: UIImage, workoutId: UUID) {
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else { return }
        Task {
            guard let ref = await auth.uploadPhoto(bucket: "workout-photos", filename: filename, jpeg: jpeg) else { return }
            // 画面が閉じている可能性があるため、元オブジェクトではなく id で引き直す。
            let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutId })
            guard let w = (try? context.fetch(descriptor))?.first, w.localPhotoFilename == filename else { return }
            w.photoURL = ref
            w.updatedAt = .now
            w.isDirty = true
            try? context.save()
            sync.enqueue(PendingChange(entity: "workouts", recordId: workoutId, operation: .upsert, updatedAt: w.updatedAt))
            // 公開済みなら feed_item の photoRef も追従させる。
            FeedPublisher.syncPublishedPosts(userId: w.userId, authorName: auth.session?.displayName,
                                             context: context, sync: sync)
        }
    }

    private func removePhoto() {
        PhotoStore.delete(workout.localPhotoFilename)
        workout.localPhotoFilename = nil
        workout.photoURL = nil
        workout.updatedAt = .now
        workout.isDirty = true
        photo = nil
        pickerItem = nil
        try? context.save()
        sync.enqueue(PendingChange(entity: "workouts", recordId: workout.id, operation: .upsert, updatedAt: workout.updatedAt))
    }
}
