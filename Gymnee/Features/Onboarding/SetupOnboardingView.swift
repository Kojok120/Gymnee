import SwiftUI
import PhotosUI

/// 起動直後の初期設定（監査T2c / 定着）。空ダッシュボードへ直行させず、
/// **アカウント名とアイコン**・週の目標・通知を最初に確定させて「自分のゴール」と再訪導線を立ち上げる。
///
/// アイコンを後回しにすると設定しないまま使い続け、フィードが既定アイコンだらけになって
/// 誰の投稿か判別できなくなる。写真を用意する負担を避けたい人のためにプリセットを用意し、
/// 1 タップで決められるようにしている。
struct SetupOnboardingView: View {
    @Environment(AuthService.self) private var auth
    @Environment(NotificationService.self) private var notifications
    @Environment(LocalSyncEngine.self) private var sync
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3
    @AppStorage("gymnee.setupDone") private var setupDone = false
    @AppStorage("gymnee.notif.prePrompted") private var notifPrePrompted = false
    @AppStorage("gymnee.avatarFilename") private var avatarFilename = ""
    @AppStorage("gymnee.avatarURL") private var avatarURLString = ""
    // 通知の種類別 ON/OFF（設定画面と共有）。オンボーディングのトグルはこれらをまとめて切り替える。
    @AppStorage(NotificationService.PrefKey.reengagement) private var notifReengagement = true
    @AppStorage(NotificationService.PrefKey.planned) private var notifPlanned = true
    @AppStorage(NotificationService.PrefKey.weeklyRecap) private var notifWeeklyRecap = true
    @State private var name = ""
    @State private var notifRequested = false
    @State private var selectedPreset: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var isSaving = false

    /// 表示名は必須（空のまま進ませない）。フレンドに「ゲスト」と表示されるのを防ぐ。
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canStart: Bool { !trimmedName.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 40)).foregroundStyle(Theme.lime)
                        Text("ようこそ Gymnee へ").font(.title3.bold())
                        Text("フレンドに表示されるプロフィールを決めましょう。")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    HStack {
                        Spacer()
                        avatarPreview
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    AvatarPickerRow(presetURLString: $selectedPreset, onPickPhoto: { showPhotoPicker = true })
                        .listRowBackground(Color.clear)
                } header: {
                    Text("アイコン")
                } footer: {
                    Text("あとから「その他 > マイページ」でいつでも変更できます。")
                }
                Section {
                    TextField("表示名（フレンドに表示されます）", text: $name)
                } header: {
                    Text("アカウント名")
                } footer: {
                    if trimmedName.isEmpty {
                        Text("始めるには入力してください。").foregroundStyle(Theme.danger)
                    }
                }
                Section {
                    Stepper(value: $weeklyGoal, in: 1...7) {
                        LabeledContent("週のワークアウト目標", value: "\(weeklyGoal) 日")
                    }
                } header: {
                    Text("今週の目標")
                } footer: {
                    Text("ホームの「今週の達成」リングの目標になります。")
                }
                Section {
                    Toggle(isOn: notificationsBinding) {
                        Label("通知を受け取る", systemImage: "bell.fill")
                    }
                } footer: {
                    Text("トレーニングを続けるためのリマインドや、フレンドからの反応をお届けします。種類ごとのオン/オフはあとから「その他 > 設定」で変更できます。")
                }
            }
            .navigationTitle("はじめに")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("始める") { finish() }.bold().disabled(!canStart)
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onAppear {
                if name.isEmpty { name = auth.session?.displayName ?? "" }
                // 既定のアイコンを 1 つ選んでおく（未設定のまま進むのを避ける。もちろん変更できる）。
                if selectedPreset == nil, avatarFilename.isEmpty, avatarURLString.isEmpty {
                    selectedPreset = AvatarPreset.urlString(symbol: AvatarPreset.symbols[0], colorIndex: 0)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    // フルデコードせず背景でダウンサンプル（巨大画像の OOM 回避）。
                    let image = await Task.detached(priority: .userInitiated) {
                        PhotoStore.downsample(data: data, maxPixel: 1024)
                    }.value
                    pickedImage = image
                    selectedPreset = nil
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let selectedPreset {
            AvatarView(urlString: selectedPreset, size: 96)
        } else if let pickedImage {
            Image(uiImage: pickedImage).resizable().scaledToFill()
                .frame(width: 96, height: 96).clipShape(Circle())
        } else {
            AvatarView(filename: avatarFilename, urlString: avatarURLString, size: 96)
        }
    }

    /// 通知トグル。オンで許可を要求し種類別設定を一括有効化、オフで種類別設定を一括無効化して
    /// 予約済みのローカル通知を取り消す（OS の許可自体はアプリから取り消せないため、
    /// アプリ内のスケジュールを止めるのが「オフ」の実体）。
    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { notifRequested },
            set: { on in
                notifRequested = on
                if on {
                    notifPrePrompted = true
                    notifReengagement = true; notifPlanned = true; notifWeeklyRecap = true
                    Task { await notifications.requestAuthorization() }
                } else {
                    notifReengagement = false; notifPlanned = false; notifWeeklyRecap = false
                    notifications.cancelReengagementReminders()
                    notifications.cancelPlannedReminders()
                    notifications.cancelWeeklyRecap()
                }
            }
        )
    }

    private func finish() {
        isSaving = true
        Task {
            auth.updateDisplayName(trimmedName)
            if let selectedPreset {
                // プリセットは擬似 URL を avatar_url に入れるだけ（アップロード不要）。
                avatarURLString = selectedPreset
                avatarFilename = ""
                auth.updateAvatarURL(selectedPreset)
            } else if let pickedImage {
                if let filename = PhotoStore.save(pickedImage) { avatarFilename = filename }
                if let jpeg = pickedImage.jpegData(compressionQuality: 0.85),
                   let url = await auth.uploadAvatar(jpeg) {
                    avatarURLString = url
                }
            }
            // updateDisplayName / updateAvatarURL はローカル更新のみ（同期は呼び出し側の責務）。
            // ここで enqueue しないと表示名がサーバへ届かず、フレンド側で「ゲスト」表示になる。
            if let uid = auth.currentUserId {
                sync.enqueue(PendingChange(entity: "profiles", recordId: uid, operation: .upsert, updatedAt: .now))
                await sync.syncNow()
            }
            isSaving = false
            setupDone = true // バインディングが false になり cover が閉じる
        }
    }
}
