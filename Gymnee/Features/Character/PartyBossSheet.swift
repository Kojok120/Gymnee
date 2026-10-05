import SwiftUI

/// 友達と倒す「週ボス」（issue #128。複数パーティは #130）。
///
/// 毎週月曜に新しいボスが来る。HP はパーティ全員の週目標の合計で、トレーニング1回が1撃。
/// 1人が削れるのは「自分の目標 + 1」まで。倒せば全員が宝箱（トロフィーとパワー）を開けられ、
/// 倒せなくてもボスが逃げるだけで罰は無い。集計も撃破の判定もサーバーが行う（`PartyService`）。
struct PartyBossSheet: View {
    let userId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(PartyService.self) private var party
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3

    /// 招待リンクから来た参加先（まだ参加していないもの）。
    @State private var pendingPartyId: UUID?
    @State private var joinMessage: String?
    @State private var isJoining = false
    @State private var openedReward: PartyBoss.Reward?
    @State private var isClaiming = false
    @State private var confirmLeave = false
    /// 新しいパーティ／名前の変更の入力（どちらも空なら名前なし＝メンバー名で表示）。
    @State private var showCreate = false
    @State private var renameTarget: PartyBoss.Status?
    @State private var nameDraft = ""
    @State private var createMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if !isSignedIn {
                        signInPrompt
                    } else {
                        if let pendingPartyId, pendingPartyId != party.status?.partyId {
                            inviteCard(pendingPartyId)
                        }
                        if !party.statuses.isEmpty {
                            partyPicker
                        }
                        if let createMessage {
                            Text(createMessage).font(.caption.bold()).foregroundStyle(Theme.warning)
                        }
                        if let status = party.status {
                            bossCard(status)
                            membersCard(status)
                            voteCard(status)
                            if status.canInvite { inviteShare(status) }
                        } else if party.isLoading {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                        } else if party.loadFailed {
                            EmptyStateView(systemImage: "wifi.exclamationmark", title: "読み込めませんでした",
                                           message: "通信できるところで、もう一度開いてください。")
                        }
                        trophyCard
                        rulesNote
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("週ボス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完了") { dismiss() } }
                if let status = party.status {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("名前を変える", systemImage: "pencil") {
                                nameDraft = status.name ?? ""
                                renameTarget = status
                            }
                            // 1人パーティしか無いなら、抜けても同じものが作り直されるだけなので出さない。
                            if party.statuses.count > 1 || status.members.count > 1 {
                                Button("このパーティを抜ける", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                    confirmLeave = true
                                }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .confirmationDialog("このパーティを抜けますか？", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("抜ける", role: .destructive) {
                    guard let id = party.status?.partyId else { return }
                    Task { await party.leave(id, userId: userId, weeklyGoal: weeklyGoal) }
                }
            } message: {
                Text("ほかのパーティはそのままです。受け取った宝箱とトロフィーも残ります。")
            }
            .alert("新しいパーティ", isPresented: $showCreate) {
                TextField("名前（例: ジム仲間）", text: $nameDraft)
                Button("作る") { Task { await createParty() } }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("別のグループで週ボスに挑めます。名前は空でもかまいません（メンバー名で表示します）。")
            }
            .alert("パーティの名前", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("名前", text: $nameDraft)
                Button("保存") {
                    guard let target = renameTarget else { return }
                    let name = PartyBoss.normalizedName(nameDraft)
                    Task { await party.rename(target.partyId, name: name, userId: userId, weeklyGoal: weeklyGoal) }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("メンバー全員の画面に出ます。空にするとメンバー名で表示します。")
            }
            .sheet(item: $openedReward) { reward in
                RewardReveal(reward: reward)
            }
            .task {
                pendingPartyId = UserDefaults.standard.string(forKey: PartyInviteLink.pendingDefaultsKey)
                    .flatMap(UUID.init(uuidString:))
                guard isSignedIn, !isDemo else { return }
                await party.refresh(userId: userId, weeklyGoal: weeklyGoal, createIfNeeded: true)
                if pendingPartyId == party.status?.partyId { clearPendingInvite() }
            }
        }
    }

    // MARK: - サインイン

    /// デモ（DEBUG の画面確認）はサーバーに行かず、`PartyService.loadDemo` の状態をそのまま描く。
    private var isDemo: Bool {
        #if DEBUG
        return DebugSupport.demoRequested
        #else
        return false
        #endif
    }

    private var isSignedIn: Bool { auth.isPermanentAccount || isDemo }

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            PixelSpriteView(sprite: PixelBossArt.sprite(bossId: currentBossId),
                            palette: PixelBossArt.palette(bossId: currentBossId), side: 96)
                .frame(maxWidth: .infinity)
            Text("週ボスはサインインすると遊べます")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            Text("友達とパーティを組んで、毎週のボスをトレーニングの回数で倒します。1人でも戦えます。")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
            BackendSignInButtons()
        }
        .gymneeCard()
    }

    private var currentBossId: String {
        party.status?.bossId ?? PartyBoss.bossId(forWeekStart: PartyBoss.weekStart(for: .now))
    }

    // MARK: - 招待を受けた

    private func inviteCard(_ partyId: UUID) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label("友達のパーティに招待されています", systemImage: "person.2.wave.2")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            Text(joinWarning)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let joinMessage {
                Text(joinMessage).font(.caption.bold()).foregroundStyle(Theme.warning)
            }
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    Task { await join(partyId) }
                } label: {
                    Text(isJoining ? "参加しています…" : "参加する").frame(maxWidth: .infinity)
                }
                .buttonStyle(.gymneePrimary(fullWidth: true))
                .disabled(isJoining)
                Button("やめておく") { clearPendingInvite() }
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
        .gymneeCard(highlighted: true)
    }

    private var joinWarning: String {
        "参加しても、いまのパーティはそのままです。トレーニング1回が、入っているすべてのパーティのボスに1撃ずつ入ります。"
    }

    private func join(_ partyId: UUID) async {
        isJoining = true
        defer { isJoining = false }
        switch await party.join(partyId, userId: userId, weeklyGoal: weeklyGoal) {
        case .success:
            clearPendingInvite()
        case .failure(.full):
            joinMessage = "このパーティは満員です（最大\(PartyBoss.maxMembers)人）。"
        case .failure(.tooMany):
            joinMessage = "入れるパーティは\(PartyBoss.maxPartiesPerUser)つまでです。どれかを抜けてから参加してください。"
        case .failure(.notFound):
            joinMessage = "このパーティは見つかりませんでした。招待した人に、新しいリンクを送ってもらってください。"
            clearPendingInvite()
        case .failure(.failed):
            joinMessage = "参加できませんでした。通信できるところで、もう一度お試しください。"
        }
    }

    private func clearPendingInvite() {
        UserDefaults.standard.removeObject(forKey: PartyInviteLink.pendingDefaultsKey)
        pendingPartyId = nil
    }

    // MARK: - パーティの切り替え

    /// 入っているパーティ（最大5つ）を横に並べる。宝箱が残っているパーティには印を付ける。
    private var partyPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(party.statuses) { status in
                    let selected = status.partyId == party.status?.partyId
                    Button { party.selectedPartyId = status.partyId } label: {
                        HStack(spacing: 6) {
                            Text(status.title(for: userId)).lineLimit(1)
                            if status.hasUnclaimedChest {
                                Circle().fill(Theme.lime).frame(width: 7, height: 7)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .foregroundStyle(selected ? Theme.onLime : Theme.textPrimary)
                        .background(selected ? Theme.limeFill : Theme.bg1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if party.canCreateParty {
                    Button {
                        nameDraft = ""
                        createMessage = nil
                        showCreate = true
                    } label: {
                        Label("新しいパーティ", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .foregroundStyle(Theme.textSecondary)
                            .overlay(Capsule().strokeBorder(Theme.bg3, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func createParty() async {
        switch await party.create(name: PartyBoss.normalizedName(nameDraft), userId: userId, weeklyGoal: weeklyGoal) {
        case .success: createMessage = nil
        case .failure(.tooMany): createMessage = "入れるパーティは\(PartyBoss.maxPartiesPerUser)つまでです。"
        case .failure: createMessage = "作れませんでした。通信できるところで、もう一度お試しください。"
        }
    }

    // MARK: - ボス

    private func bossCard(_ status: PartyBoss.Status) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                BossSpriteView(bossId: status.bossId, tier: status.tier, side: 144)
                    .opacity(status.defeated ? 0.35 : 1)
                    .rotationEffect(.degrees(status.defeated ? -8 : 0))
                if status.defeated {
                    Text("撃破！")
                        .font(.pixel(size: 28, relativeTo: .title))
                        .foregroundStyle(Theme.lime)
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                }
            }
            VStack(spacing: 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    BossTierBadge(tier: status.tier)
                    Text(status.boss?.name ?? "今週のボス")
                        .font(.pixel(size: 20, relativeTo: .title3))
                        .foregroundStyle(Theme.textPrimary)
                }
                if let flavor = status.boss?.flavor {
                    Text(flavor).font(.caption).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            hpBar(status)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("HP \(status.remainingHP) / \(status.hp)")
                        .font(.caption.monospacedDigit().bold()).foregroundStyle(Theme.textPrimary)
                    Text("倒すと EXP +\(status.rewardExp)")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text(status.defeated ? "来週の月曜に次のボスが来ます"
                     : "あと\(PartyBoss.daysLeft(in: status.weekStart, now: .now))日で逃げます")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            if status.hasUnclaimedChest {
                Button {
                    Task {
                        isClaiming = true
                        openedReward = await party.claim(status.partyId, userId: userId, weeklyGoal: weeklyGoal)
                        isClaiming = false
                    }
                } label: {
                    Label(isClaiming ? "開けています…" : "宝箱を開ける", systemImage: "gift.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gymneePrimary(fullWidth: true))
                .disabled(isClaiming)
            }
        }
        .frame(maxWidth: .infinity)
        .gymneeCard(highlighted: status.hasUnclaimedChest)
    }

    /// HP を1撃ぶんずつのマスで見せる（削れたマスが減っていく）。
    private func hpBar(_ status: PartyBoss.Status) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<max(status.hp, 1), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index < status.remainingHP ? Theme.danger : Theme.bg3)
                    .frame(height: 12)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("ボスの残り HP \(status.remainingHP)、最大 \(status.hp)")
    }

    // MARK: - メンバー

    private func membersCard(_ status: PartyBoss.Status) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: status.members.count > 1
                          ? "\(status.title(for: userId))（\(status.members.count)人）"
                          : "ソロで挑戦中")
            ForEach(status.members) { member in
                HStack(spacing: Theme.Spacing.md) {
                    AvatarView(urlString: member.avatarURL, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.id == userId ? "\(member.displayName)（あなた）" : member.displayName)
                            .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("今週 \(member.hits)回 / 目標 \(member.weeklyGoal)回")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                    hitPips(member)
                }
            }
        }
        .gymneeCard()
    }

    /// 1撃ぶんの丸。目標の数＋上乗せ1つ（目標を超えた1回までダメージになる）。
    private func hitPips(_ member: PartyBoss.Member) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<(member.weeklyGoal + 1), id: \.self) { index in
                Circle()
                    .fill(index < member.damage ? Theme.lime : Theme.bg3)
                    .overlay {
                        if index == member.weeklyGoal {
                            Circle().strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        }
                    }
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(member.damage)撃")
    }

    private func inviteShare(_ status: PartyBoss.Status) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ShareLink(item: PartyInviteLink.url(for: status.partyId), message: Text(PartyInviteLink.shareMessage)) {
                Label("友達をパーティに誘う", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("このパーティには、あと\(PartyBoss.maxMembers - status.members.count)人誘えます。人数が増えるとボスの HP も増えます。")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - 翌週のランクの投票（issue #133）

    private func voteCard(_ status: PartyBoss.Status) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "来週のボスの強さ")
            Text("日曜 23:59 に締め切り。多数決で決まり、同票なら弱い方、票が無ければ中くらいです。")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(PartyBoss.Tier.allCases) { tier in
                    let mine = status.myNextVote == tier
                    Button {
                        Task { await party.vote(tier, partyId: status.partyId, userId: userId, weeklyGoal: weeklyGoal) }
                    } label: {
                        VStack(spacing: 4) {
                            BossSpriteView(bossId: PartyBoss.bossId(forWeekStart: nextWeekStart(status)),
                                           tier: tier, side: 52)
                            BossTierBadge(tier: tier)
                            Text("EXP +\(tier.rewardExp)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                            Text(tier.hpRule).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                            Text("\(status.nextVotes[tier] ?? 0)票")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(mine ? Theme.lime : Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(mine ? Theme.lime : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tier.label)に投票。いま\(status.nextVotes[tier] ?? 0)票\(mine ? "、あなたの票" : "")")
                }
            }
        }
        .gymneeCard()
    }

    private func nextWeekStart(_ status: PartyBoss.Status) -> Date {
        PartyBoss.calendar.date(byAdding: .day, value: 7, to: status.weekStart) ?? status.weekStart
    }

    // MARK: - 図鑑

    private var trophyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "ボス図鑑")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      spacing: Theme.Spacing.sm) {
                ForEach(PartyBoss.trophies(from: party.rewards), id: \.boss.id) { entry in
                    VStack(spacing: 4) {
                        PixelSpriteView(sprite: PixelBossArt.sprite(bossId: entry.boss.id),
                                        palette: entry.defeats > 0 ? PixelBossArt.palette(bossId: entry.boss.id) : Self.silhouette,
                                        side: 48)
                        Text(entry.defeats > 0 ? entry.boss.name : "？？？")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(entry.defeats > 0 ? "×\(entry.defeats)" : "未撃破")
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(entry.defeats > 0 ? Theme.lime : Theme.textTertiary)
                    }
                }
            }
        }
        .gymneeCard()
    }

    /// 未撃破のボスは影だけ見せる。
    private static let silhouette: PixelPalette = {
        var palette = PixelPalette.neutral
        palette.accent = Color(hexF: 0x3A3F3B)
        palette.accentShade = Color(hexF: 0x2C302D)
        palette.light = Color(hexF: 0x3A3F3B)
        palette.eye = Color(hexF: 0x3A3F3B)
        palette.dark = Color(hexF: 0x2C302D)
        palette.wood = Color(hexF: 0x2C302D)
        palette.cloth = Color(hexF: 0x3A3F3B)
        return palette
    }()

    private var rulesNote: some View {
        Text("トレーニングを1回記録するごとに、入っているすべてのパーティのボスに1撃。HP はパーティ全員の週目標の合計で、1人が削れるのは目標＋1回までです。パーティは\(PartyBoss.maxPartiesPerUser)つまで入れます。月曜 0時にボスが入れ替わり、倒せなかったボスは逃げるだけです。")
            .font(.caption2).foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension PartyBoss.Reward: Identifiable {
    var id: Date { weekStart }
}

/// 宝箱を開けたときの演出。トロフィー（倒したボス）とパワーを見せる。
private struct RewardReveal: View {
    let reward: PartyBoss.Reward
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            BossSpriteView(bossId: reward.bossId, tier: reward.tier, side: 120)
            HStack(spacing: Theme.Spacing.sm) {
                BossTierBadge(tier: reward.tier)
                Text("\(PartyBoss.boss(id: reward.bossId)?.name ?? "ボス")のトロフィー")
                    .font(.pixel(size: 20, relativeTo: .title3)).foregroundStyle(Theme.textPrimary)
            }
            if reward.exp > 0 {
                Label("EXP +\(reward.exp)", systemImage: "sparkles")
                    .font(.headline).foregroundStyle(Theme.lime)
            }
            Label("テストステロンパワー +\(reward.energy)", systemImage: "bolt.heart.fill")
                .font(.headline).foregroundStyle(Theme.lime)
            Text("図鑑に記録しました。EXP はキャラの成長に、パワーは遠征に使えます。")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("いいね") { dismiss() }
                .buttonStyle(.gymneePrimary(fullWidth: true))
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.bg0)
        .presentationDetents([.medium])
    }
}
