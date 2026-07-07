import SwiftUI
import SwiftData
import AuthenticationServices

/// 設定（§5 / §7）。HealthKit・通知・エクスポート・サブスク・データ削除の各導線。
/// P0 ではプロフィール・同期状態・サインアウト・データ削除を実装。各機能は対応フェーズで有効化する。
struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(HealthKitService.self) private var health
    @Environment(AppErrorCenter.self) private var errors
    @Environment(SubscriptionService.self) private var subscription
    @Environment(NotificationService.self) private var notifications
    @Environment(CalendarService.self) private var calendarService
    @Environment(GoogleCalendarService.self) private var googleCalendar
    @Environment(\.modelContext) private var context
    @State private var showDeleteConfirm = false
    @State private var showEmailSignIn = false
    @State private var showProfileEdit = false
    @State private var showPaywall = false
    @State private var browserURL: IdentifiableURL?
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue
    @AppStorage("gymnee.avatarFilename") private var avatarFilename = ""
    @AppStorage("gymnee.avatarURL") private var avatarURLString = ""
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal: Int = 3
    // 記録のレスト既定秒数（RestTimer が参照）。
    @AppStorage("gymnee.restSeconds") private var restSeconds: Int = 90
    // 通知の種類別 ON/OFF。ローカル通知はこの @AppStorage を NotificationService が参照。
    @AppStorage(NotificationService.PrefKey.streak) private var notifStreak = true
    @AppStorage(NotificationService.PrefKey.planned) private var notifPlanned = true
    @AppStorage(NotificationService.PrefKey.weeklyRecap) private var notifWeeklyRecap = true
    // プッシュ通知（いいね/フレンドのチェックイン）は profiles 列が真実の情報源。
    @Query private var profiles: [Profile]

    var body: some View {
        Form {
            Section("プロフィール") {
                Button { showProfileEdit = true } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        AvatarView(filename: avatarFilename, urlString: avatarURLString, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.session?.displayName ?? "—").foregroundStyle(.primary)
                            Text("プロフィールを編集").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
                if let id = auth.currentUserId {
                    LabeledContent("ユーザーID") {
                        Text(id.uuidString.prefix(8) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker("投稿の既定の公開範囲", selection: $defaultVisibilityRaw) {
                    ForEach(Visibility.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }
            } header: {
                Text("ソーシャル")
            } footer: {
                Text("チェックインやワークアウトを共有するときの初期の公開範囲。投稿ごとに個別変更もできます。")
            }

            Section {
                Stepper(value: $weeklyGoal, in: 1...7) {
                    LabeledContent("週のワークアウト目標", value: "\(weeklyGoal) 日")
                }
                Stepper(value: $restSeconds, in: 30...300, step: 5) {
                    LabeledContent("レストタイマー", value: "\(restSeconds) 秒")
                }
            } header: {
                Text("ワークアウト")
            } footer: {
                Text("「今週の達成」リングの目標日数と、セット記録後に始まるレストの既定秒数。")
            }

            Section {
                switch notifications.status {
                case .authorized, .provisional, .ephemeral:
                    EmptyView()
                case .denied:
                    Button {
                        notifications.openSystemSettings()
                    } label: {
                        Label("通知をオンにする（設定を開く）", systemImage: "bell.badge")
                    }
                default:
                    Button {
                        Task { await notifications.requestAuthorization() }
                    } label: {
                        Label("通知をオンにする", systemImage: "bell")
                    }
                }

                // 種類別トグル（許諾が無い間は無効表示）。
                Group {
                    Toggle("いいね", isOn: pushBinding(\.notifyLikes))
                        .disabled(myProfile == nil)
                    Toggle("コメント", isOn: pushBinding(\.notifyComments))
                        .disabled(myProfile == nil)
                    Toggle("フレンドのチェックイン", isOn: pushBinding(\.notifyFriendCheckin))
                        .disabled(myProfile == nil)
                    Toggle("連続記録の途切れ予告", isOn: $notifStreak)
                        .onChange(of: notifStreak) { _, on in if !on { notifications.cancelStreakReminder() } }
                    Toggle("予定ワークアウト", isOn: $notifPlanned)
                        .onChange(of: notifPlanned) { _, on in if !on { notifications.cancelPlannedReminders() } }
                    Toggle("今週のまとめ", isOn: $notifWeeklyRecap)
                        .onChange(of: notifWeeklyRecap) { _, on in if !on { notifications.cancelWeeklyRecap() } }
                }
                .disabled(!notifAuthorized)
            } header: {
                Text("通知")
            } footer: {
                Text(notifAuthorized
                     ? "受け取りたい通知の種類を選べます。"
                     : "通知をオンにすると、種類ごとに受け取り設定ができます。")
            }
            .task { await notifications.refreshStatus() }

            Section("同期") {
                LabeledContent("バックエンド", value: sync.isRemoteEnabled ? "接続済み" : "ローカルのみ")
                if sync.isRemoteEnabled {
                    LabeledContent("認証", value: auth.isBackendAuthenticated ? "サインイン済み" : "未サインイン")
                    LabeledContent("未同期の変更", value: "\(sync.pendingCount) 件")
                    if let last = sync.lastSyncedAt {
                        LabeledContent("最終同期", value: last.formatted(.relative(presentation: .named)))
                    }
                    if let err = sync.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button {
                        Task { await sync.syncNow(force: true) }
                    } label: {
                        Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if !auth.isBackendAuthenticated {
                        SignInWithAppleButton(.signIn) { request in
                            auth.prepareAppleRequest(request)
                        } onCompletion: { result in
                            Task { await auth.completeSignInWithApple(result) }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 44)
                        Button { Task { await auth.signInWithGoogle() } } label: {
                            Label("Google で続ける", systemImage: "globe")
                        }
                        Button { showEmailSignIn = true } label: {
                            Label("メールで続ける", systemImage: "envelope.fill")
                        }
                        Text("サインインすると、これまでのローカル記録もクラウドに同期されます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("未同期の変更", value: "\(sync.pendingCount) 件")
                    Text("現在はローカルのみで動作中（Supabase 未設定）。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("データ") {
                Button {
                    Task { await health.requestAuthorization() }
                } label: {
                    HStack {
                        Label("ヘルスケア連携", systemImage: "heart.fill")
                        Spacer()
                        Text(health.isAvailable ? (health.isAuthorized ? "許可済み" : "許可する") : "非対応")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
                .disabled(!health.isAvailable)
            }

            Section {
                LabeledContent("現在のプラン", value: subscription.isPremium ? "Premium" : "Free")
                if SubscriptionService.planOverrideAvailable {
                    Toggle("Premium として表示（テスト用）", isOn: Bindable(subscription).planOverride)
                        .tint(Theme.lime)
                }
                if !subscription.isPremium {
                    Button { showPaywall = true } label: {
                        Label("Premium にアップグレード", systemImage: "crown.fill")
                    }
                    .tint(Theme.lime)
                } else {
                    Button("購入を復元") { Task { await subscription.restore() } }
                        .tint(.primary)
                }
            } header: {
                Text("プラン")
            } footer: {
                if SubscriptionService.planOverrideAvailable {
                    Text("TestFlight・開発ビルドのみ表示。Free/Premium を切り替えて動作確認できます（本番では表示されません）。")
                }
            }

            Section {
                CalendarLinkRows()
            } header: {
                Text("カレンダー連携")
            } footer: {
                Text("予定を週プランナーに重ねて表示し、計画作成時に Google カレンダーへ自動で予定を追加します。Apple の「連携を解除」はアプリ内で予定を非表示にするだけです（OS の許可取り消しは iOS の設定 → プライバシーから）。")
            }

            Section("規約・サポート") {
                Button { browserURL = IdentifiableURL(url: LegalLinks.terms) } label: {
                    legalRow("利用規約", systemImage: "doc.text")
                }
                .tint(.primary)
                Button { browserURL = IdentifiableURL(url: LegalLinks.privacy) } label: {
                    legalRow("プライバシーポリシー", systemImage: "hand.raised")
                }
                .tint(.primary)
                Link(destination: Self.contactURL) {
                    legalRow("お問い合わせ", systemImage: "envelope")
                }
                .tint(.primary)
            }

            Section {
                Button("サインアウト", role: .destructive) {
                    auth.signOut()
                }
                Button("すべてのデータを削除", role: .destructive) {
                    showDeleteConfirm = true
                }
            } footer: {
                Text("個人情報保護法（APPI）準拠：データの削除・エクスポートを提供します（§7）。")
            }

            Section {
                LabeledContent("バージョン", value: appVersion)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("すべてのデータを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除する", role: .destructive) { deleteAllData() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この端末上の全記録が消えます。元に戻せません。")
        }
        .sheet(isPresented: $showEmailSignIn) {
            EmailSignInSheet()
        }
        .sheet(isPresented: $showProfileEdit) {
            ProfileEditView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(item: $browserURL) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
    }

    // 規約・プライバシーの URL は LegalLinks（単一の出所）を参照する。
    // 件名「Gymnee お問い合わせ」を percent-encode（生の日本語だと URL(string:) が nil になり得るため）。
    private static let contactURL = URL(string: "mailto:kojokamo120@gmail.com?subject=Gymnee%20%E3%81%8A%E5%95%8F%E3%81%84%E5%90%88%E3%82%8F%E3%81%9B")!

    /// 規約・サポート行（左ラベル＋右に外部リンクの示唆アイコン）。
    private func legalRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    /// 通知が許諾済みか（種類別トグルの有効/無効の判定）。
    private var notifAuthorized: Bool {
        switch notifications.status {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// 自分のプロフィール行（プッシュ通知設定の保存先）。
    private var myProfile: Profile? {
        guard let uid = auth.currentUserId else { return nil }
        return profiles.first { $0.id == uid }
    }

    /// プッシュ通知トグル（profiles 列を直接読み書き＋同期キューへ）。
    private func pushBinding(_ keyPath: ReferenceWritableKeyPath<Profile, Bool>) -> Binding<Bool> {
        Binding(
            get: { myProfile?[keyPath: keyPath] ?? true },
            set: { newValue in
                guard let p = myProfile else { return }
                p[keyPath: keyPath] = newValue
                p.updatedAt = .now
                p.isDirty = true
                try? context.save()
                sync.enqueue(PendingChange(entity: "profiles", recordId: p.id, operation: .upsert, updatedAt: p.updatedAt))
            }
        )
    }

    /// ローカルデータの全削除（§7 データ削除）。
    private func deleteAllData() {
        try? context.delete(model: Profile.self)
        try? context.delete(model: Gym.self)
        try? context.delete(model: GymEquipment.self)
        try? context.delete(model: Visit.self)
        try? context.delete(model: VisitPartner.self)
        try? context.delete(model: Workout.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: WorkoutExercise.self)
        try? context.delete(model: ExerciseSet.self)
        try? context.delete(model: Routine.self)
        try? context.delete(model: RoutineExercise.self)
        try? context.delete(model: PersonalRecord.self)
        try? context.delete(model: BodyMetric.self)
        try? context.delete(model: ProgressPhoto.self)
        try? context.delete(model: Follow.self)
        try? context.delete(model: Block.self)
        try? context.delete(model: Report.self)
        try? context.delete(model: FeedItem.self)
        try? context.delete(model: Product.self)
        try? context.delete(model: SupplyLog.self)
        try? context.delete(model: Subscription.self)
        do {
            try context.save()
        } catch {
            errors.report("データの削除に失敗しました。\(error.localizedDescription)")
            return
        }
        // リモート接続時はサーバ側のアカウント（auth.users → 全データ CASCADE）も削除する。
        Task {
            let ok = await auth.deleteAccount()
            if !ok {
                errors.report("サーバ側データの削除に失敗しました。時間をおいて再度お試しください。")
            }
        }
    }
}

// MARK: - カレンダー連携（共用）

/// カレンダー連携の行（Apple/Google の接続・解除）。設定画面と週プランナーの連携シートで共用する。
struct CalendarLinkRows: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(GoogleCalendarService.self) private var googleCalendar

    var body: some View {
        if calendarService.authorized {
            if calendarService.isEnabled {
                LabeledContent("Apple カレンダー", value: "連携中")
                Button("Apple 連携を解除", role: .destructive) { calendarService.isEnabled = false }
            } else {
                LabeledContent("Apple カレンダー", value: "オフ")
                Button { calendarService.isEnabled = true } label: {
                    Label("Apple カレンダーと連携", systemImage: "calendar.badge.plus")
                }
                .tint(Theme.lime)
            }
        } else {
            Button { Task { await calendarService.requestAccess() } } label: {
                Label("Apple カレンダーと連携", systemImage: "calendar.badge.plus")
            }
            .tint(Theme.lime)
        }
        if googleCalendar.isConfigured {
            if googleCalendar.isSignedIn {
                LabeledContent("Google カレンダー", value: googleCalendar.email ?? "連携済み")
                if !googleCalendar.isConnected {
                    Button { Task { await googleCalendar.connect() } } label: {
                        Label("カレンダー権限を許可（再連携）", systemImage: "exclamationmark.triangle")
                    }
                    .tint(.orange)
                }
                Button("Google 連携を解除", role: .destructive) { googleCalendar.disconnect() }
            } else {
                Button { Task { await googleCalendar.connect() } } label: {
                    Label("Google カレンダーと連携", systemImage: "calendar.badge.plus")
                }
                .tint(Theme.lime)
            }
        } else {
            LabeledContent("Google カレンダー", value: "未設定")
        }
        if let err = googleCalendar.lastError {
            Text(err).font(.caption).foregroundStyle(.secondary)
        }
    }
}
