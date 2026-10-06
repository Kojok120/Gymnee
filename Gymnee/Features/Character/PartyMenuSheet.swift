import SwiftUI

/// 週ボスの「パーティ」メニュー（issue #137。元は #128 の週ボス画面そのもの）。
///
/// 戦闘画面（`BossBattleView`）から開く。パーティの切り替え・作成・名前・脱退、メンバーとジョブ、
/// 今週の戦いの記録、招待、翌週のランクの投票、図鑑、遊び方を置く。
/// 集計も撃破の判定もサーバーが行う（`PartyService`）。
struct PartyMenuSheet: View {
    let userId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(PartyService.self) private var party
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3

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
                    if !party.statuses.isEmpty {
                        partyPicker
                    }
                    if let createMessage {
                        Text(createMessage).font(.caption.bold()).foregroundStyle(Theme.warning)
                    }
                    if let status = party.status {
                        membersCard(status)
                        battleLogCard(status)
                        voteCard(status)
                        if status.canInvite { inviteShare(status) }
                    }
                    trophyCard
                    jobsCard
                    rulesNote
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.bg0)
            .navigationTitle("パーティ")
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
        }
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

    // MARK: - メンバー

    private func membersCard(_ status: PartyBoss.Status) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: status.members.count > 1
                          ? "\(status.title(for: userId))（\(status.members.count)人）"
                          : "ソロで挑戦中")
            HStack {
                Text("HP \(status.remainingHP) / \(status.hp)")
                    .font(.caption.monospacedDigit().bold()).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("連携 \(status.comboCount)回 ・ 倒すと EXP +\(status.rewardExp)")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            ForEach(status.members) { member in
                HStack(spacing: Theme.Spacing.md) {
                    AvatarView(urlString: member.avatarURL, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(member.id == userId ? "\(member.displayName)（あなた）" : member.displayName)
                                .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Label(member.job.label, systemImage: member.job.symbol)
                                .font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
                            if member.liveSessionId != nil {
                                Text("戦闘中").font(.caption2.bold()).foregroundStyle(Theme.lime)
                            }
                        }
                        Text("今週 \(member.hits)回 / 目標 \(member.weeklyGoal)回 ・ \(member.job.skillName)"
                             + (status.skillTriggered(by: member.id) ? " 発動ずみ" : " まだ"))
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

    // MARK: - 戦いの記録

    private func battleLogCard(_ status: PartyBoss.Status) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "今週の戦い")
            if status.attacks.isEmpty {
                Text("まだ誰も攻撃していません。トレーニングを1回記録すると、ボスに1撃入ります。")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(status.attacks.reversed()) { attack in
                HStack(spacing: Theme.Spacing.sm) {
                    Text(weekday(attack))
                        .font(.caption2.bold()).foregroundStyle(Theme.textTertiary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(PartyBattle.name(of: attack.userId, in: status, userId: userId))の \(attack.category.move(seed: attack.id))")
                            .font(.subheadline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        if let bonus = bonusText(attack, status: status) {
                            Text(bonus).font(.caption2).foregroundStyle(Theme.lime)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(attack.total > 0 ? "\(attack.total)" : "上限")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(attack.total > 0 ? Theme.textPrimary : Theme.textTertiary)
                }
            }
        }
        .gymneeCard()
    }

    private func weekday(_ attack: PartyBoss.Attack) -> String {
        guard let date = attack.date else { return "" }
        return ["月", "火", "水", "木", "金", "土", "日"][PartyBoss.isoWeekday(date) - 1]
    }

    private func bonusText(_ attack: PartyBoss.Attack, status: PartyBoss.Status) -> String? {
        var parts: [String] = []
        if attack.combo > 0 { parts.append("連携 +1") }
        if attack.skill > 0 { parts.append("\((status.member(attack.userId)?.job ?? .hero).skillName) +1") }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }

    private func inviteShare(_ status: PartyBoss.Status) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ShareLink(item: PartyInviteLink.url(for: status.partyId), message: Text(PartyInviteLink.shareMessage)) {
                Label("友達をパーティに誘う", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("このパーティには、あと\(PartyBoss.maxMembers - status.members.count)人誘えます。人数が増えるとボスの HP も増えますが、同じ日に攻撃すると連携攻撃で上乗せできます。")
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

    // MARK: - 遊び方

    /// ジョブとスキルの一覧。自分のジョブがどう決まったかも分かるようにする。
    private var jobsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "ジョブとスキル")
            Text("最近4週間に一番多く鍛えた系統が半分を超えると、そのジョブになります（月曜に決まり、週の途中では変わりません）。スキルは1人週1回、ダメージ +1。")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(PartyBoss.Job.allCases, id: \.self) { job in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: job.symbol)
                        .font(.subheadline)
                        .foregroundStyle(job == party.status?.member(userId)?.job ? Theme.lime : Theme.textSecondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(job.label) ・ \(job.skillName)")
                            .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                        Text(job.skillRule).font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(job.origin).font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .gymneeCard()
    }

    private var rulesNote: some View {
        Text("トレーニングを1回記録するごとに、入っているすべてのパーティのボスに1撃（1人あたり目標＋1回まで）。同じ日に2人以上が攻撃すると連携攻撃で +1。HP はパーティ全員の週目標の合計で、ランクで変わります。パーティは\(PartyBoss.maxPartiesPerUser)つまで入れます。残り HP が1になると、ほかのメンバーに「あと1撃」を知らせます。月曜 0時にボスが入れ替わり、倒せなかったボスは逃げるだけです。")
            .font(.caption2).foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
