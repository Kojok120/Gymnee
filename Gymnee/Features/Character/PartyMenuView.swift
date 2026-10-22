import SwiftUI

/// 週ボスの「パーティ」メニュー（issue #137 → #161 で RPG のメニュー画面に作り直し）。
///
/// ボス部屋（`BossBattleView`）の上に重ねる全画面のメニュー。上でパーティを切り替え（＋で作る）、
/// 左のコマンドで「なかま / きろく / つぎのボス / ずかん / あそびかた」を選び、右の窓に中身を出す。
/// 以前は iOS のシートに説明文の段落を並べていて、文字が多くて頭に入らなかった。
/// ここでは絵・マス・数で見せ、きまりの説明は「あそびかた」と「？」の中だけに置く。
/// 名前の変更・脱退・作成もゲームの窓で聞く（iOS の確認窓は使わない）。
/// 集計も撃破の判定もサーバーが行う（`PartyService`）。
struct PartyMenuView: View {
    enum Page: String, CaseIterable, Identifiable {
        case members, log, vote, trophies, rules

        var id: String { rawValue }

        var title: String {
            switch self {
            case .members: return "なかま"
            case .log: return "きろく"
            case .vote: return "つぎのボス"
            case .trophies: return "ずかん"
            case .rules: return "あそびかた"
            }
        }
    }

    /// メニューの上に重ねる小窓。
    private enum Popup: Equatable {
        case options
        case rename
        case create
        case confirmLeave
        case voteRules
    }

    let userId: UUID
    /// 自分の姿（仲間の姿が載っていないときの元にもする）。
    let selfLook: PixelCharacterRenderer.Look
    var initialPage: Page = .members
    let onClose: () -> Void

    @Environment(PartyService.self) private var party
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3

    @State private var page: Page = .members
    @State private var popup: Popup?
    /// 新しいパーティ／名前の変更の入力（空なら名前なし＝メンバー名で表示）。
    @State private var nameDraft = ""
    /// 失敗などの一言（下の帯に出す）。
    @State private var notice: String?
    @FocusState private var nameFocused: Bool

    private static let commandWidth: CGFloat = 124

    var body: some View {
        ZStack {
            // 後ろのボス部屋は暗くするだけ（押しても何も起きない）。
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(spacing: Theme.Spacing.sm) {
                partyTabs
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    commandWindow
                    contentWindow
                }
                .frame(maxHeight: .infinity, alignment: .top)
                bottomBar
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            if let popup {
                popupLayer(popup)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .onAppear { page = initialPage }
    }

    // MARK: - パーティのタブ

    /// 入っているパーティ（最大5つ）を横に並べる。宝箱が残っているパーティには緑の印。＋で作る。
    private var partyTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(party.statuses) { status in
                    let selected = status.partyId == party.status?.partyId
                    Button {
                        GameSound.play(.select)
                        party.selectedPartyId = status.partyId
                    } label: {
                        HStack(spacing: 6) {
                            Text(status.title(for: userId)).lineLimit(1)
                            if status.hasUnclaimedChest {
                                Rectangle().fill(GameWindowStyle.accent).frame(width: 6, height: 6)
                            }
                        }
                        .font(.pixel(size: 14, relativeTo: .subheadline))
                        .foregroundStyle(selected ? Color.white : GameWindowStyle.muted)
                        .padding(.horizontal, Theme.Spacing.md)
                        .frame(height: 36)
                        .background(GameWindowStyle.fill, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(selected ? Color.white : Color.white.opacity(0.35), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                if party.canCreateParty {
                    Button {
                        GameSound.play(.select)
                        nameDraft = ""
                        notice = nil
                        popup = .create
                    } label: {
                        Text("＋")
                            .font(.pixel(size: 16, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 36)
                            .background(GameWindowStyle.fill, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.35), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新しいパーティを作る")
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - コマンドと中身

    private var commandWindow: some View {
        VStack(spacing: 0) {
            ForEach(Page.allCases) { item in
                GameCommand(title: item.title, selected: page == item, size: 15) { page = item }
            }
        }
        .gameWindow(padding: Theme.Spacing.sm)
        .frame(width: Self.commandWidth)
    }

    private var contentWindow: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let status = party.status {
                    switch page {
                    case .members: membersPage(status)
                    case .log: logPage(status)
                    case .vote: votePage(status)
                    case .trophies: trophiesPage
                    case .rules: rulesPage(status)
                    }
                } else {
                    switch page {
                    case .trophies: trophiesPage
                    case .rules: rulesPage(nil)
                    default:
                        Text(party.loadFailed ? "よみこめなかった…" : "よみこみちゅう…")
                            .font(.pixel(size: 14)).foregroundStyle(GameWindowStyle.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .gameWindow(padding: Theme.Spacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 窓の見出し。右に小さな四角のボタン（「…」「？」）を置ける。
    private func pageHeader(_ title: String, button: String? = nil, label: String = "", action: @escaping () -> Void = {}) -> some View {
        HStack {
            Text(title).font(.pixel(size: 16, relativeTo: .headline)).foregroundStyle(.white)
            Spacer(minLength: 0)
            if let button {
                Button {
                    GameSound.play(.select)
                    action()
                } label: {
                    Text(button)
                        .font(.pixel(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white, lineWidth: 2))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
            }
        }
        .frame(minHeight: 44)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
    }

    // MARK: - なかま

    private func membersPage(_ status: PartyBoss.Status) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader("なかま", button: "…", label: "パーティの名前と脱退") { popup = .options }
            ForEach(status.members) { member in
                divider
                memberRow(member)
            }
            if status.canInvite {
                divider
                ShareLink(item: PartyInviteLink.url(for: status.partyId), message: Text(PartyInviteLink.shareMessage)) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("＋")
                            .font(.pixel(size: 14))
                            .frame(width: 26, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                        Text("さそう").font(.pixel(size: 14))
                        Spacer(minLength: 0)
                        Text("あき \(PartyBoss.maxMembers - status.members.count)")
                            .font(.pixel(size: 12)).foregroundStyle(GameWindowStyle.muted)
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .simultaneousGesture(TapGesture().onEnded { GameSound.play(.select) })
                .accessibilityLabel("友達をパーティに誘う。あと\(PartyBoss.maxMembers - status.members.count)人")
            }
        }
    }

    private func memberRow(_ member: PartyBoss.Member) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            PixelCharacterFigure(look: member.id == userId ? selfLook : .partyMember(member, base: selfLook))
                .frame(width: 30, height: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.id == userId ? "あなた" : member.displayName)
                    .font(.pixel(size: 14)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    Text(member.job.label).font(.pixel(size: 11)).foregroundStyle(GameWindowStyle.muted)
                    if member.liveSessionId != nil {
                        Text("トレ中")
                            .font(.pixel(size: 10)).foregroundStyle(.black)
                            .padding(.horizontal, 3)
                            .background(GameWindowStyle.accent)
                    }
                }
            }
            Spacer(minLength: 0)
            HitPipsView(pips: member.pips, side: 8)
        }
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
    }

    // MARK: - きろく

    private func logPage(_ status: PartyBoss.Status) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader("こんしゅうの たたかい")
            if status.attacks.isEmpty {
                Text("まだ だれも こうげき していない")
                    .font(.pixel(size: 13)).foregroundStyle(GameWindowStyle.muted)
            }
            ForEach(status.attacks.reversed()) { attack in
                divider
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(weekday(attack))
                        .font(.pixel(size: 11)).foregroundStyle(GameWindowStyle.muted)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(PartyBattle.name(of: attack.userId, in: status, userId: userId))の")
                            .font(.pixel(size: 11)).foregroundStyle(GameWindowStyle.muted).lineLimit(1)
                        Text(attack.category.move(seed: attack.id))
                            .font(.pixel(size: 14)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                        if let bonus = bonusText(attack, status: status) {
                            Text(bonus).font(.pixel(size: 11)).foregroundStyle(GameWindowStyle.accent)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(attack.total > 0 ? "\(attack.total)" : "上限")
                        .font(.pixel(size: 15).monospacedDigit())
                        .foregroundStyle(attack.total > 0 ? Color.white : GameWindowStyle.muted)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func weekday(_ attack: PartyBoss.Attack) -> String {
        guard let date = attack.date else { return "" }
        return ["月", "火", "水", "木", "金", "土", "日"][PartyBoss.isoWeekday(date) - 1]
    }

    private func bonusText(_ attack: PartyBoss.Attack, status: PartyBoss.Status) -> String? {
        var parts: [String] = []
        if attack.isSpecial { parts.append("必殺技") }
        if attack.combo > 0 { parts.append("連携 +1") }
        if attack.skill > 0 { parts.append("\((status.member(attack.userId)?.job ?? .hero).skillName) +1") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - つぎのボス（翌週のランクの投票。issue #133）

    private func votePage(_ status: PartyBoss.Status) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            pageHeader("つぎのボス", button: "？", label: "投票のきまり") { popup = .voteRules }
            ForEach(PartyBoss.Tier.allCases) { tier in
                voteRow(tier, status: status)
            }
        }
    }

    private func voteRow(_ tier: PartyBoss.Tier, status: PartyBoss.Status) -> some View {
        let mine = status.myNextVote == tier
        let votes = status.nextVotes[tier] ?? 0
        return Button {
            GameSound.play(.select)
            Task { await party.vote(tier, partyId: status.partyId, userId: userId, weeklyGoal: weeklyGoal) }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                BossSpriteView(bossId: PartyBoss.displayBossId(forWeekStart: nextWeekStart(status)), tier: tier, side: 46)
                    .frame(width: 60)
                VStack(alignment: .leading, spacing: 4) {
                    BossTierBadge(tier: tier)
                    Text("EXP \(tier.rewardExp)").font(.pixel(size: 11).monospacedDigit()).foregroundStyle(GameWindowStyle.muted)
                }
                Spacer(minLength: 0)
                // 票は四角の数（緑があなたの票）。
                HStack(spacing: 3) {
                    ForEach(0..<votes, id: \.self) { index in
                        Rectangle()
                            .fill(mine && index == 0 ? GameWindowStyle.accent : Color.white)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(mine ? GameWindowStyle.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.label)に投票。いま\(votes)票\(mine ? "、あなたの票" : "")")
    }

    private func nextWeekStart(_ status: PartyBoss.Status) -> Date {
        PartyBoss.calendar.date(byAdding: .day, value: 7, to: status.weekStart) ?? status.weekStart
    }

    // MARK: - ずかん

    private var trophiesPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader("ボスずかん")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      spacing: Theme.Spacing.md) {
                ForEach(PartyBoss.trophies(from: party.rewards), id: \.boss.id) { entry in
                    VStack(spacing: 3) {
                        PixelSpriteView(sprite: PixelBossArt.sprite(bossId: entry.boss.id),
                                        palette: entry.defeats > 0 ? PixelBossArt.palette(bossId: entry.boss.id) : Self.silhouette,
                                        side: 40)
                        Text(entry.defeats > 0 ? entry.boss.name : "？？？")
                            .font(.pixel(size: 10)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(entry.defeats > 0 ? "×\(entry.defeats)" : (SeasonalEvent.event(bossId: entry.boss.id) != nil ? "きかんげんてい" : "-"))
                            .font(.pixel(size: 10).monospacedDigit())
                            .foregroundStyle(entry.defeats > 0 ? GameWindowStyle.accent : GameWindowStyle.muted)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
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

    // MARK: - あそびかた

    private func rulesPage(_ status: PartyBoss.Status?) -> some View {
        let myJob = status?.member(userId)?.job
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            pageHeader("あそびかた")
            ForEach(PartyBoss.howToPlay, id: \.self) { line in
                ruleLine(line)
            }
            divider.padding(.vertical, Theme.Spacing.xs)
            Text("ジョブ").font(.pixel(size: 16, relativeTo: .headline)).foregroundStyle(.white)
            ruleLine("4週間で いちばん きたえた 部位で きまる（月曜）")
            ForEach(PartyBoss.Job.allCases, id: \.self) { job in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        GameCursor(visible: job == myJob, dot: 1.5)
                        Text("\(job.label)・\(job.skillName)")
                            .font(.pixel(size: 14)).foregroundStyle(job == myJob ? GameWindowStyle.accent : .white)
                    }
                    Text(job.skillRule)
                        .font(.pixel(size: 12)).foregroundStyle(GameWindowStyle.muted)
                        .padding(.leading, 15)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func ruleLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Rectangle().fill(GameWindowStyle.accent).frame(width: 5, height: 5)
            Text(text)
                .font(.pixel(size: 13)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 下の帯

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(notice ?? "")
                .font(.pixel(size: 13)).foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            GameCommand(title: "とじる", selected: true, size: 16, action: onClose)
                .fixedSize()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .gameWindow(padding: 4)
    }

    // MARK: - 小窓

    @ViewBuilder
    private func popupLayer(_ popup: Popup) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if popup != .confirmLeave { closePopup() } }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                switch popup {
                case .options: optionsPopup
                case .rename: namePopup(title: "パーティの なまえ", confirm: "けってい") { rename() }
                case .create: namePopup(title: "あたらしい パーティ", confirm: "つくる") { create() }
                case .confirmLeave: leavePopup
                case .voteRules: voteRulesPopup
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
            .gameWindow()
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .transition(.opacity)
    }

    private func closePopup() {
        nameFocused = false
        popup = nil
    }

    private var optionsPopup: some View {
        VStack(alignment: .leading, spacing: 0) {
            GameCommand(title: "なまえを かえる", selected: true, size: 16) {
                nameDraft = party.status?.name ?? ""
                popup = .rename
            }
            // 1人パーティしか無いなら、抜けても同じものが作り直されるだけなので出さない。
            if let status = party.status, party.statuses.count > 1 || status.members.count > 1 {
                GameCommand(title: "パーティを ぬける", size: 16) { popup = .confirmLeave }
            }
            GameCommand(title: "やめる", size: 16) { closePopup() }
        }
    }

    private func namePopup(title: String, confirm: String, onConfirm: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(.pixel(size: 16, relativeTo: .headline)).foregroundStyle(.white)
            TextField("", text: $nameDraft, prompt: Text("なかまの なまえで でる").foregroundStyle(GameWindowStyle.muted))
                .font(.pixel(size: 16))
                .foregroundStyle(.white)
                .tint(GameWindowStyle.accent)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit(onConfirm)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white).frame(height: 2) }
                .onAppear { nameFocused = true }
            HStack(spacing: Theme.Spacing.lg) {
                GameCommand(title: confirm, selected: true, size: 17, action: onConfirm)
                GameCommand(title: "やめる", size: 17) { closePopup() }
            }
        }
    }

    private var leavePopup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("この パーティを ぬけますか？").font(.pixel(size: 16)).foregroundStyle(.white)
            Text("宝箱と トロフィーは のこる").font(.pixel(size: 13)).foregroundStyle(GameWindowStyle.muted)
            HStack(spacing: Theme.Spacing.lg) {
                GameCommand(title: "はい", selected: true, size: 17) { leave() }
                GameCommand(title: "いいえ", size: 17) { closePopup() }
            }
        }
    }

    private var voteRulesPopup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("とうひょうの きまり").font(.pixel(size: 16, relativeTo: .headline)).foregroundStyle(.white)
            ForEach(PartyBoss.voteRules, id: \.self) { line in
                ruleLine(line)
            }
            GameCommand(title: "とじる", selected: true, size: 16) { closePopup() }
                .fixedSize()
        }
    }

    // MARK: - 操作

    private func rename() {
        guard let status = party.status else { return closePopup() }
        let name = PartyBoss.normalizedName(nameDraft)
        closePopup()
        Task { await party.rename(status.partyId, name: name, userId: userId, weeklyGoal: weeklyGoal) }
    }

    private func create() {
        let name = PartyBoss.normalizedName(nameDraft)
        closePopup()
        Task {
            switch await party.create(name: name, userId: userId, weeklyGoal: weeklyGoal) {
            case .success: notice = nil
            case .failure(.tooMany): notice = "パーティは \(PartyBoss.maxPartiesPerUser)つ まで"
            case .failure: notice = "つくれなかった。通信を たしかめて もう一度"
            }
        }
    }

    private func leave() {
        guard let id = party.status?.partyId else { return closePopup() }
        closePopup()
        Task { await party.leave(id, userId: userId, weeklyGoal: weeklyGoal) }
    }
}
