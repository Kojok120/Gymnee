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
    @Environment(NotificationService.self) private var notifications
    @Environment(StoreService.self) private var store
    @Environment(CalendarService.self) private var calendarService
    @Environment(GoogleCalendarService.self) private var googleCalendar
    @Environment(\.modelContext) private var context
    @State private var showDeleteConfirm = false
    @State private var showCoachDeleteConfirm = false
    @State private var showEmailSignIn = false
    @State private var showProfileEdit = false
    @State private var browserURL: IdentifiableURL?
    /// CSV 書き出し結果（分析画面から移設）。
    @State private var csvURL: URL?
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    /// ユーザーIDをコピーしたことの一時表示。
    @State private var copiedUserId = false
    /// フル再取得の実行中フラグ。
    @State private var isRefetching = false
    @AppStorage("gymnee.defaultVisibility") private var defaultVisibilityRaw = Visibility.friends.rawValue
    @AppStorage("gymnee.avatarFilename") private var avatarFilename = ""
    @AppStorage("gymnee.avatarURL") private var avatarURLString = ""
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal: Int = 3
    // 記録のレスト既定秒数（RestTimer が参照）。
    @AppStorage("gymnee.restSeconds") private var restSeconds: Int = 90
    // レスト終了チャイム（RestChime が参照。サイレントスイッチでも鳴る）。
    @AppStorage(RestChime.enabledKey) private var restSoundEnabled = true
    // AI コーチの関わり方（#79）。育成タブのコーチ表示とチャットの挙動を決める。
    @AppStorage(CoachMode.storageKey) private var coachModeRaw = CoachMode.default.rawValue
    // 通知の種類別 ON/OFF。ローカル通知はこの @AppStorage を NotificationService が参照。
    @AppStorage(NotificationService.PrefKey.coach) private var notifCoach = true
    @AppStorage(NotificationService.PrefKey.streak) private var notifStreak = true
    @AppStorage(NotificationService.PrefKey.planned) private var notifPlanned = true
    @AppStorage(NotificationService.PrefKey.weeklyRecap) private var notifWeeklyRecap = true
    // プッシュ通知（いいね/コメント）は profiles 列が真実の情報源。
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
                    // 問い合わせのときに読み上げ・コピーできる必要があるので、
                    // 見切れさせず全桁を出す（先頭 8 桁だけだと「…」で切れて用を成さない）。
                    // 長いので値だけを次の行に置き、タップでコピーできるようにする。
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ユーザーID")
                            .foregroundStyle(.primary)
                        Text(id.uuidString.lowercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIPasteboard.general.string = id.uuidString.lowercased()
                        copiedUserId = true
                    }
                    if copiedUserId {
                        Text("コピーしました")
                            .font(.caption2)
                            .foregroundStyle(Theme.lime)
                    }
                }
            }

            Section {
                Picker("投稿の既定の公開範囲", selection: $defaultVisibilityRaw) {
                    ForEach(Visibility.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }
                if let uid = auth.currentUserId {
                    // 値ベース遷移（クロージャ型だと BlockedUsersView の init が Form 描画のたびに
                    // @Query を作り直し、iOS 26 系でメインスレッドハングの条件になる）。
                    NavigationLink(value: AppRoute.blockedUsers(uid)) {
                        Label("ブロック中のユーザー", systemImage: "hand.raised")
                    }
                }
            } header: {
                Text("ソーシャル")
            } footer: {
                Text("ワークアウトを共有するときの初期の公開範囲。投稿ごとに個別変更もできます。ブロックした相手はいつでも解除できます。")
            }

            Section {
                Stepper(value: $weeklyGoal, in: 1...7) {
                    LabeledContent("週のワークアウト目標", value: "\(weeklyGoal) 日")
                }
                Stepper(value: $restSeconds, in: 30...300, step: 5) {
                    LabeledContent("レストタイマー", value: "\(restSeconds) 秒")
                }
                Toggle("レスト終了に音を鳴らす", isOn: $restSoundEnabled)
            } header: {
                Text("ワークアウト")
            } footer: {
                Text("「今週の達成」リングの目標日数と、セット記録後に始まるレストの既定秒数。終了音はマナーモードでも鳴ります（アプリを開いている間）。")
            }

            Section {
                Picker("コーチ", selection: $coachModeRaw) {
                    ForEach(CoachMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(coachMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } header: {
                Text("AIコーチ")
            } footer: {
                Text("コーチは記録だけを根拠に助言します。育成タブに用事があるときだけ現れ、タップで相談できます。オフにすると一切現れません。")
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
                    Toggle("コーチの声かけ", isOn: $notifCoach)
                        .onChange(of: notifCoach) { _, on in
                            if !on { notifications.cancelCoachNotices() }
                        }
                        .disabled(coachMode == .off)
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

            Section {
                LabeledContent("バックエンド", value: sync.isRemoteEnabled ? "接続済み" : "ローカルのみ")
                if sync.isRemoteEnabled {
                    // 匿名（ゲスト）セッションは同期は動くが「サインイン済み」とは表示しない。
                    LabeledContent("認証", value: auth.isPermanentAccount ? "サインイン済み" : "未サインイン")
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
                    // 差分同期は「前回どこまで取ったか」を基準にするため、端末側だけが空になると
                    // 「取得済み」と判断されて永久に戻ってこない。その手動の脱出口。
                    Button {
                        Task {
                            isRefetching = true
                            sync.resetPullWatermarks()
                            await sync.syncNow(force: true)
                            isRefetching = false
                        }
                    } label: {
                        if isRefetching {
                            HStack(spacing: Theme.Spacing.sm) {
                                ProgressView().controlSize(.small)
                                Text("取り直しています…")
                            }
                        } else {
                            Label("サーバーから全部取り直す", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(isRefetching)
                    if !auth.isPermanentAccount {
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
                        Text("サインインすると、これまでの記録を引き継いだまま複数端末・フレンド機能が使えます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("未同期の変更", value: "\(sync.pendingCount) 件")
                    Text("現在はローカルのみで動作中（Supabase 未設定）。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("同期")
            } footer: {
                Text("記録はサーバーにも保存されます。手元の表示が実際より少ないときは「サーバーから全部取り直す」を押してください。")
            }

            // 非消耗型（見た目）の復元導線。Apple は復元手段を必須にするので、
            // 審査担当者が最初に探すこの場所に置く（レビューノートにもこのパスを書く）。
            Section {
                Button {
                    Task { await restorePurchases() }
                } label: {
                    HStack {
                        Label("購入を復元", systemImage: "arrow.clockwise")
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                }
                .tint(.primary)
                .disabled(isRestoring)

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Toggle("（開発）見た目を全部解錠", isOn: Bindable(store).debugUnlockAll)
                #endif
            } header: {
                Text("購入")
            } footer: {
                Text("購入した見た目は Apple ID に紐づきます。機種変更や再インストールのあとはここから復元してください。")
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

                // CSV エクスポートは分析画面から移設（分析は人体図 1 枚に絞ったため）。
                Button {
                    guard let uid = auth.currentUserId else { return }
                    csvURL = CSVExporter.writeTempFile(
                        CSVExporter.workoutsCSV(userId: uid, context: context), name: "gymnee_workouts")
                } label: {
                    Label("記録を CSV で書き出す", systemImage: "square.and.arrow.up")
                }
                .tint(.primary)
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("共有: \(csvURL.lastPathComponent)", systemImage: "doc")
                    }
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
                // サインアウトは本人性のあるアカウントのみ表示する。匿名（ゲスト）セッションで
                // サインアウトすると匿名アカウントに二度と戻れず記録が孤児化するため出さない。
                if auth.isPermanentAccount {
                    Button("サインアウト", role: .destructive) {
                        auth.signOut()
                    }
                }
                // コーチとの会話だけを消せるようにする。体調や体の話をする相手なので、
                // 「消したければアカウントごと」しか手が無いのは筋が悪い。
                if coachMessageCount > 0 {
                    Button("コーチとの会話を削除", role: .destructive) {
                        showCoachDeleteConfirm = true
                    }
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
        .confirmationDialog("コーチとの会話を削除しますか？", isPresented: $showCoachDeleteConfirm, titleVisibility: .visible) {
            Button("削除する", role: .destructive) { deleteCoachMessages() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("これまでの相談がすべて消えます（記録・クエストは残ります）。元に戻せません。")
        }
        .sheet(isPresented: $showEmailSignIn) {
            EmailSignInSheet()
        }
        .sheet(isPresented: $showProfileEdit) {
            ProfileEditView()
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

    /// 選択中のコーチの関わり方。
    private var coachMode: CoachMode { CoachMode(rawValue: coachModeRaw) ?? .default }

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

    /// コーチとの会話の件数（0 件なら削除ボタンを出さない）。
    private var coachMessageCount: Int {
        (try? context.fetchCount(FetchDescriptor<CoachMessage>())) ?? 0
    }

    /// コーチとの会話だけを削除する（記録・クエストには触らない）。
    /// サーバー側（`coach_messages`）も outbox 経由で消す。RLS は本人のみ削除可。
    private func deleteCoachMessages() {
        let messages = (try? context.fetch(FetchDescriptor<CoachMessage>())) ?? []
        guard !messages.isEmpty else { return }
        // ローカルを消す前に id を控える（削除後はモデルから読めない）。
        let changes = messages.map {
            PendingChange(entity: "coach_messages", recordId: $0.id, operation: .delete, updatedAt: .now)
        }
        for message in messages { context.delete(message) }
        do {
            try context.save()
        } catch {
            errors.report("会話の削除に失敗しました。\(error.localizedDescription)")
            return
        }
        sync.enqueueBatch(changes)
    }

    /// 購入の復元。結果を握り潰すと「復元しました」と嘘をつくことになるので、件数と失敗を出し分ける。
    private func restorePurchases() async {
        isRestoring = true
        restoreMessage = nil
        defer { isRestoring = false }
        let outcome = await store.restore()
        if case .failed = outcome {
            errors.report(outcome.message)
        } else {
            restoreMessage = outcome.message
        }
    }

    /// ローカルデータの全削除（§7 データ削除）。
    /// **`GymneeSchema` のモデルを 1 つ残らず消す**。消し漏れがあると「全部消した」と言いながら
    /// 会話や育成データが残る（実際に 9 型が漏れていた）。モデルを足したらここにも足すこと。
    private func deleteAllData() {
        try? context.delete(model: Profile.self)
        try? context.delete(model: Workout.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: WorkoutExercise.self)
        try? context.delete(model: ExerciseSet.self)
        try? context.delete(model: PersonalRecord.self)
        try? context.delete(model: BodyMetric.self)
        try? context.delete(model: ProgressPhoto.self)
        try? context.delete(model: Follow.self)
        try? context.delete(model: Block.self)
        try? context.delete(model: Report.self)
        try? context.delete(model: FeedItem.self)
        try? context.delete(model: PostReaction.self)
        try? context.delete(model: Comment.self)
        try? context.delete(model: PlannedWorkout.self)
        try? context.delete(model: Product.self)
        try? context.delete(model: SupplyLog.self)
        try? context.delete(model: Subscription.self)
        try? context.delete(model: ExpeditionRun.self)
        try? context.delete(model: CharacterLoadout.self)
        try? context.delete(model: CharacterStyle.self)
        try? context.delete(model: PetState.self)
        try? context.delete(model: CoachMessage.self)
        try? context.delete(model: RoomPickupRecord.self)
        // 差分同期の基準も捨てる。残すと「消したのに次の同期で取り直さない」状態になる。
        try? context.delete(model: SyncWatermark.self)
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
