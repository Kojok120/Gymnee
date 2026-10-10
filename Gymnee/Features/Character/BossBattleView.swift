import SwiftUI

/// 週ボスの戦闘画面（issue #137。仕組みは #128 / #130 / #133）。
///
/// 全画面の石壁のボス部屋。奥にボス、手前に仲間が背中を向けて並ぶ（背面視点）。
/// 開くと、前回見たあとに入った仲間の攻撃を順に再生し、メッセージ窓で読ませる。
/// ダメージ・撃破・報酬はサーバーが正（`PartyService`）。ここは見せ方だけを持つ。
/// パーティの切り替え・招待・投票・図鑑・戦いの記録は「パーティ」メニュー（`PartyMenuSheet`）。
struct BossBattleView: View {
    let userId: UUID
    /// 自分の姿（部屋で組み立てたもの。サーバーに載せた見た目より新しい）。
    let selfLook: PixelCharacterRenderer.Look
    /// 連れているペット（ソロのとき仲間として並ぶ）。
    let pet: PetCatalog.Pet?

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(PartyService.self) private var party
    @Environment(LiveSessionService.self) private var live
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3

    // 再生
    @State private var replay = PartyBattle.Replay.empty
    /// 再生しているパーティと、その時点の攻撃（同じ内容で再読み込みされても再生し直さない）。
    @State private var replayKey = ""
    /// 再生中の段（nil = 再生していない）。
    @State private var playIndex: Int?
    @State private var playToken = 0
    @State private var stepStartedAt = Date.distantPast
    @State private var visibleLines = 0
    @State private var shownHP = 0
    @State private var defeatStartedAt: Date?
    @State private var sceneStart = Date.now

    // 画面
    @State private var selectedActor: BattleActorID?
    @State private var showMenu = false
    @State private var openedReward: PartyBoss.Reward?
    @State private var isClaiming = false
    @State private var toast: String?
    @State private var cheered: Set<UUID> = []
    @State private var pendingPartyId: UUID?
    @State private var joinMessage: String?
    @State private var isJoining = false

    private static let plate = Color.black.opacity(0.55)
    private static let accent = Color(hexF: 0xC6FF3D)
    private static let hpRed = Color(hexF: 0xFF4D4D)
    private static let messageHeight: CGFloat = 112
    private static let toolbarHeight: CGFloat = 52
    /// 未サインインのときのサインインの案内（Apple・Google・メールの3つ）の高さの目安。
    private static let signInHeight: CGFloat = 196

    var body: some View {
        GeometryReader { outer in
            let safe = outer.safeAreaInsets
            GeometryReader { proxy in
                scene(size: proxy.size, safe: safe)
            }
            .ignoresSafeArea()
        }
        .background(Color(hexF: 0x0D0F15))
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sheet(isPresented: $showMenu) {
            PartyMenuSheet(userId: userId)
        }
        .sheet(item: $openedReward) { reward in
            BossRewardReveal(reward: reward)
        }
        .task {
            pendingPartyId = UserDefaults.standard.string(forKey: PartyInviteLink.pendingDefaultsKey)
                .flatMap(UUID.init(uuidString:))
            guard isSignedIn else { return }
            if !isDemo {
                await party.refresh(userId: userId, weeklyGoal: weeklyGoal, createIfNeeded: true)
            }
            if pendingPartyId == party.status?.partyId { clearPendingInvite() }
            startReplayIfNeeded()
        }
        .task(id: playToken) { await play() }
        .onChange(of: statusKey) { _, _ in startReplayIfNeeded() }
        .onDisappear { finishReplay(markOnly: true) }
    }

    // MARK: - 状態

    private var isDemo: Bool {
        #if DEBUG
        return DebugSupport.demoRequested
        #else
        return false
        #endif
    }

    private var isSignedIn: Bool { auth.isPermanentAccount || isDemo }
    private var status: PartyBoss.Status? { party.status }

    private var bossId: String {
        status?.bossId ?? PartyBoss.bossId(forWeekStart: PartyBoss.weekStart(for: .now))
    }

    private var tier: PartyBoss.Tier { status?.tier ?? .medium }

    /// 再生し直すかの判定に使う（パーティと攻撃の顔ぶれ）。
    private var statusKey: String {
        guard let status else { return "" }
        return status.partyId.uuidString + "|" + status.attacks.map(\.id).joined(separator: ",")
    }

    private var currentStep: PartyBattle.Step? {
        guard let playIndex, replay.steps.indices.contains(playIndex) else { return nil }
        return replay.steps[playIndex]
    }

    private var defeatStepIndex: Int? { replay.steps.firstIndex(where: \.defeats) }

    /// ボスが消えているか（倒れきった後）。再生中で、まだ撃破の段に来ていなければ立っている。
    private var bossGone: Bool {
        guard let status, status.defeated else { return false }
        if let playIndex, let defeat = defeatStepIndex, playIndex <= defeat, defeatStartedAt == nil { return false }
        return true
    }

    // MARK: - 再生

    private func startReplayIfNeeded() {
        guard let status else { return }
        guard statusKey != replayKey else { return }
        // 再生中に新しい攻撃が届いたら、今の再生を見せ切ってから（次に開いたときに）見せる。
        if playIndex != nil, replayKey.hasPrefix(status.partyId.uuidString) { return }
        replayKey = statusKey
        defeatStartedAt = nil
        let seen = party.seenAttackIds(partyId: status.partyId, weekStart: status.weekStart)
        replay = PartyBattle.replay(status: status, seen: seen, userId: userId)
        visibleLines = 0
        if replay.steps.isEmpty {
            playIndex = nil
            shownHP = status.remainingHP
        } else {
            shownHP = replay.startHP
            playIndex = 0
        }
        // 別のパーティの再生が流れていたら止める（眠っている間に前の HP を書き戻させない）。
        playToken += 1
    }

    /// 段を順に流す。タップで次の段へ飛ぶときは playToken を変えて流し直す。
    private func play() async {
        // playToken は再生を止めるためにも変わるので、再生していなければ何もしない
        // （ここで終了処理をすると、終了処理が playToken を変えて自分を呼び直し続ける）。
        guard playIndex != nil else { return }
        while let index = playIndex, replay.steps.indices.contains(index) {
            let step = replay.steps[index]
            if let defeat = defeatStepIndex, index > defeat, defeatStartedAt == nil { defeatStartedAt = .now }
            stepStartedAt = .now
            visibleLines = 0
            shownHP = step.hpBefore
            guard await pause(BossBattleStage.impactAt) else { return }
            withAnimation(.smooth(duration: 0.5)) { shownHP = step.hpAfter }
            if step.defeats { defeatStartedAt = .now }
            for line in 1...max(1, lines(for: step, at: index).count) {
                visibleLines = line
                guard await pause(0.75) else { return }
            }
            guard await pause(0.6) else { return }
            playIndex = index + 1 < replay.steps.count ? index + 1 : nil
        }
        finishReplay(markOnly: false)
    }

    /// 待つ。取り消されたら false。
    private func pause(_ seconds: TimeInterval) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func advance() {
        guard let index = playIndex else { return }
        if index + 1 < replay.steps.count {
            playIndex = index + 1
            playToken += 1
        } else {
            finishReplay(markOnly: false)
        }
    }

    /// 再生を終える（見た攻撃を記録する）。`markOnly` は画面を閉じたとき（表示は触らない）。
    private func finishReplay(markOnly: Bool) {
        guard let status else { return }
        party.markSeen(status.attacks.map(\.id), partyId: status.partyId, weekStart: status.weekStart)
        guard !markOnly else { return }
        if status.defeated, defeatStartedAt == nil, defeatStepIndex != nil { defeatStartedAt = .now }
        playIndex = nil
        playToken += 1
        withAnimation(.smooth) { shownHP = status.remainingHP }
    }

    private func lines(for step: PartyBattle.Step, at index: Int) -> [String] {
        index == 0 && replay.skipped > 0 ? ["ほか \(replay.skipped)回の 攻撃が あった…"] + step.lines : step.lines
    }

    // MARK: - 画面

    private func actors() -> [BossBattleStage.Actor] {
        guard let status else {
            return [BossBattleStage.Actor(id: .member(userId), look: selfLook, pet: nil, name: "あなた", job: nil, isLive: false)]
        }
        let me = status.member(userId)
        let selfActor = BossBattleStage.Actor(
            id: .member(userId), look: selfLook, pet: nil, name: "あなた",
            job: me?.job, isLive: me?.liveSessionId != nil
        )
        // ソロはコーチとペットが仲間として並ぶ（ダメージは無い）。
        if status.members.count <= 1 {
            var cast = [coachActor, selfActor]
            if let pet {
                cast.append(BossBattleStage.Actor(id: .pet, look: nil, pet: pet, name: pet.name, job: nil, isLive: false))
            }
            return cast
        }
        let others = status.members.filter { $0.id != userId }.map { member in
            BossBattleStage.Actor(
                id: .member(member.id), look: look(for: member), pet: nil, name: member.displayName,
                job: member.job, isLive: member.liveSessionId != nil
            )
        }
        // 自分を真ん中に置く。
        var cast = others
        cast.insert(selfActor, at: min(others.count, others.count / 2))
        return cast
    }

    private var coachActor: BossBattleStage.Actor {
        BossBattleStage.Actor(
            id: .coach,
            look: PixelCharacterRenderer.Look(
                build: PixelCharacterRenderer.coachBuild, skin: PixelCharacterRenderer.coachSkin,
                equipped: [:], stage: .rookie, carriesPack: false, nameTag: nil, role: .coach
            ),
            pet: nil, name: "コーチ", job: nil, isLive: false
        )
    }

    /// 仲間の姿。見た目が載っていなければ、部屋の合トレ仲間と同じく ID から決まる色で描く。
    private func look(for member: PartyBoss.Member) -> PixelCharacterRenderer.Look {
        if let look = member.look {
            return PixelCharacterRenderer.Look(
                build: look.build,
                skin: SkinCatalog.skin(id: look.skinId),
                equipped: look.equippedItems,
                stage: look.stageValue,
                carriesPack: false,
                nameTag: nil,
                role: .trainee,
                hairStyleId: PixelHairArt.style(id: look.hairStyleId).id,
                accessoryId: PixelHairArt.accessory(id: look.accessoryId).id,
                gender: look.genderValue
            )
        }
        let seed = DeterministicRandom.seed(from: member.id)
        var fallback = selfLook
        fallback.skin = SkinCatalog.all[Int(seed % UInt64(SkinCatalog.all.count))]
        fallback.equipped = [:]
        fallback.stage = .rookie
        fallback.hairStyleId = PixelHairArt.defaultStyleId
        fallback.accessoryId = "none"
        return fallback
    }

    /// 下に積むもの（メッセージ窓と下の帯）の高さ。仲間はこの上に立つ。
    private func bottomReserve(safe: EdgeInsets) -> CGFloat {
        let toolbar = isSignedIn ? Self.toolbarHeight : Self.signInHeight
        return Self.messageHeight + toolbar + safe.bottom + Theme.Spacing.sm
    }

    @ViewBuilder
    private func scene(size: CGSize, safe: EdgeInsets) -> some View {
        let cast = actors()
        let layout = BattleLayout(
            size: size, bottomReserve: bottomReserve(safe: safe), actors: cast.map(\.id),
            bossSprite: PixelBossArt.sprite(bossId: bossId, tier: tier), tier: tier
        )
        ZStack(alignment: .topLeading) {
            DungeonBackdrop(horizon: layout.horizon / max(size.height, 1), dot: layout.dot,
                            bossTint: PixelBossArt.palette(bossId: bossId).accent)
            BossBattleStage(
                layout: layout, bossId: bossId, tier: tier, actors: cast,
                strike: strikeFX(), defeatStartedAt: defeatStartedAt, bossGone: bossGone,
                angry: isAngry, chestOpened: chestState, sceneStart: sceneStart
            )
            hitTargets(layout: layout, cast: cast)
            bossGauge(layout: layout)
            topBar(safe: safe)
            VStack(spacing: Theme.Spacing.sm) {
                Spacer()
                if let pendingPartyId, isSignedIn, pendingPartyId != status?.partyId {
                    inviteCard(pendingPartyId)
                }
                if let selectedActor {
                    actorCard(selectedActor)
                }
                messageWindow
                toolbar
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, safe.bottom + Theme.Spacing.sm)
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
    }

    private var isAngry: Bool {
        guard let status, !status.defeated, status.hp > 0 else { return false }
        return shownHP * 2 <= status.hp
    }

    /// 宝箱（ボスが消えた後）。nil は出さない。
    private var chestState: Bool? {
        guard let status, status.defeated, playIndex == nil else { return nil }
        return status.claimed
    }

    private func strikeFX() -> BossBattleStage.Strike? {
        guard let step = currentStep, let status else { return nil }
        var bonuses: [String] = []
        if step.attack.combo > 0 { bonuses.append("連携 +1") }
        if step.attack.skill > 0 {
            bonuses.append("\((status.member(step.attack.userId)?.job ?? .hero).skillName) +1")
        }
        return BossBattleStage.Strike(
            actor: .member(step.attack.userId), startedAt: stepStartedAt,
            damage: step.attack.base, bonuses: bonuses
        )
    }

    // MARK: - タップ

    private func hitTargets(layout: BattleLayout, cast: [BossBattleStage.Actor]) -> some View {
        ZStack(alignment: .topLeading) {
            // 何もないところのタップで、選択を外す／再生を送る。
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedActor != nil { selectedActor = nil } else { advance() }
                }
            ForEach(cast) { actor in
                if let rect = layout.hitRect(for: actor.id) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture { selectedActor = selectedActor == actor.id ? nil : actor.id }
                        .accessibilityElement()
                        .accessibilityLabel(actor.name + (actor.job.map { "、\($0.label)" } ?? ""))
                        .accessibilityAddTraits(.isButton)
                }
            }
            if let opened = chestState, !opened {
                let rect = layout.chestRect
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .onTapGesture { claim() }
                    .accessibilityElement()
                    .accessibilityLabel("宝箱を開ける")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func claim() {
        guard let status, status.hasUnclaimedChest, !isClaiming else { return }
        Task {
            isClaiming = true
            openedReward = await party.claim(status.partyId, userId: userId, weeklyGoal: weeklyGoal)
            isClaiming = false
        }
    }

    // MARK: - 上の帯

    private func topBar(safe: EdgeInsets) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Self.plate, in: Circle())
            }
            .accessibilityLabel("閉じる")
            Spacer(minLength: 0)
            if isSignedIn, !party.statuses.isEmpty {
                partySwitcher
            }
            Spacer(minLength: 0)
            if let status {
                Text(status.defeated ? "撃破" : "あと\(PartyBoss.daysLeft(in: status.weekStart, now: .now))日")
                    .font(.pixel(size: 13, relativeTo: .caption))
                    .foregroundStyle(status.defeated ? Self.accent : .white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(height: 38)
                    .background(Self.plate, in: Capsule())
            } else {
                Color.clear.frame(width: 38, height: 38)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, safe.top + Theme.Spacing.xs)
    }

    /// 入っているパーティの切り替え。1つなら名前だけ出す。
    private var partySwitcher: some View {
        Menu {
            ForEach(party.statuses) { candidate in
                Button {
                    party.selectedPartyId = candidate.partyId
                    selectedActor = nil
                } label: {
                    if candidate.partyId == status?.partyId {
                        Label(candidate.title(for: userId), systemImage: "checkmark")
                    } else {
                        Text(candidate.title(for: userId) + (candidate.hasUnclaimedChest ? "（宝箱）" : ""))
                    }
                }
            }
            Divider()
            Button("パーティのメニュー", systemImage: "person.3") { showMenu = true }
        } label: {
            HStack(spacing: 6) {
                Text(status?.title(for: userId) ?? "パーティ")
                    .lineLimit(1)
                if party.statuses.count > 1 {
                    Image(systemName: "chevron.down").font(.caption2.bold())
                }
                if party.statuses.contains(where: { $0.hasUnclaimedChest && $0.partyId != status?.partyId }) {
                    Circle().fill(Self.accent).frame(width: 7, height: 7)
                }
            }
            .font(.pixel(size: 13, relativeTo: .subheadline))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 38)
            .background(Self.plate, in: Capsule())
        }
    }

    // MARK: - ボスの名前と HP

    private func bossGauge(layout: BattleLayout) -> some View {
        let hp = max(status?.hp ?? 0, 1)
        let ratio = min(1, max(0, Double(shownHP) / Double(hp)))
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                BossTierBadge(tier: tier)
                Text(PartyBoss.boss(id: bossId)?.name ?? "今週のボス")
                    .font(.pixel(size: 17, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
            }
            if let status {
                HStack(spacing: 6) {
                    Text("HP")
                        .font(.pixel(size: 11, relativeTo: .caption2))
                        .foregroundStyle(Self.accent)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.black.opacity(0.7))
                        Rectangle().fill(ratio <= 0.25 ? Self.hpRed : Color(hexF: 0xFF8A3D))
                            .frame(width: 168 * ratio)
                    }
                    .frame(width: 168, height: 10)
                    .overlay(Rectangle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2))
                    Text("\(shownHP)/\(status.hp)")
                        .font(.pixel(size: 11, relativeTo: .caption2).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 5)
                .background(Self.plate, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityElement()
                .accessibilityLabel("ボスの残り HP \(shownHP)、最大 \(status.hp)")
            }
        }
        .frame(width: layout.size.width)
        .offset(y: max(layout.bossTop - 62, 96))
    }

    // MARK: - メッセージ窓

    private var messageWindow: some View {
        // 再生していないときの言葉は時刻で入れ替わるので、4秒ごとに描き直す。
        TimelineView(.periodic(from: .now, by: 4)) { timeline in
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(messageLines(at: timeline.date).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.pixel(size: 15, relativeTo: .body))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .frame(height: Self.messageHeight)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white, lineWidth: 2.5))
        .overlay(alignment: .bottomTrailing) {
            if playIndex != nil {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.sm)
                    .symbolEffect(.pulse)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .animation(.easeOut(duration: 0.15), value: visibleLines)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(playIndex != nil ? .isButton : [])
        .accessibilityHint(playIndex != nil ? "タップで次へ" : "")
    }

    /// いま窓に出す行。再生中はその段の行、それ以外は状況に応じた言葉を入れ替えて出す。
    private func messageLines(at now: Date) -> [String] {
        if let toast { return [toast] }
        if !isSignedIn {
            return ["\(PartyBoss.boss(id: bossId)?.name ?? "ボス")が まちかまえている！", "サインインすると 仲間と 戦える"]
        }
        if let step = currentStep, let index = playIndex {
            return Array(lines(for: step, at: index).prefix(max(1, visibleLines)))
        }
        guard let status else {
            if party.loadFailed { return ["読み込めなかった…", "通信できるところで もう一度 開こう"] }
            return ["ダンジョンに はいった…"]
        }
        let messages = PartyBattle.idleMessages(status: status, userId: userId, now: now)
        let index = Int(now.timeIntervalSince1970 / 4) % max(messages.count, 1)
        return messages[index].components(separatedBy: "\n")
    }

    // MARK: - 下の帯

    @ViewBuilder
    private var toolbar: some View {
        if isSignedIn {
            signedInToolbar
        } else {
            BackendSignInButtons()
                .padding(Theme.Spacing.md)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var signedInToolbar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            toolbarButton("パーティ", "person.3.fill") { showMenu = true }
            if let status, status.canInvite {
                ShareLink(item: PartyInviteLink.url(for: status.partyId), message: Text(PartyInviteLink.shareMessage)) {
                    toolbarLabel("仲間を誘う", "person.badge.plus")
                }
            }
            if let status, status.hasUnclaimedChest, playIndex == nil {
                toolbarButton(isClaiming ? "開けています…" : "宝箱を開ける", "gift.fill", highlighted: true) { claim() }
            }
        }
        .frame(height: Self.toolbarHeight)
        .frame(maxWidth: .infinity)
    }

    private func toolbarButton(_ title: String, _ symbol: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolbarLabel(title, symbol, highlighted: highlighted) }
            .buttonStyle(.plain)
    }

    private func toolbarLabel(_ title: String, _ symbol: String, highlighted: Bool = false) -> some View {
        Label(title, systemImage: symbol)
            .font(.pixel(size: 13, relativeTo: .subheadline))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(highlighted ? Color.black : .white)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(highlighted ? Self.accent : Self.plate, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }

    // MARK: - 仲間の情報

    @ViewBuilder
    private func actorCard(_ actor: BattleActorID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch actor {
            case .coach:
                Text("コーチ").font(.pixel(size: 15)).foregroundStyle(.white)
                Text("ソロのときに付き添う応援役。ダメージは入らない。仲間を誘うと、連携攻撃ができるようになる。")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
            case .pet:
                Text(pet?.name ?? "ペット").font(.pixel(size: 15)).foregroundStyle(.white)
                Text("いっしょに来てくれた。ダメージは入らない。")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
            case let .member(id):
                if let member = status?.member(id) {
                    memberDetail(member)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private func memberDetail(_ member: PartyBoss.Member) -> some View {
        let isMe = member.id == userId
        HStack(spacing: Theme.Spacing.sm) {
            Text(isMe ? "\(member.displayName)（あなた）" : member.displayName)
                .font(.pixel(size: 15)).foregroundStyle(.white).lineLimit(1)
            Label(member.job.label, systemImage: member.job.symbol)
                .font(.caption.bold()).foregroundStyle(Self.accent)
            Spacer(minLength: 0)
            Text("今週 \(member.hits) / 目標 \(member.weeklyGoal)")
                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
        }
        let triggered = status?.skillTriggered(by: member.id) ?? false
        Text("\(member.job.skillName): \(member.job.skillRule)" + (triggered ? "（今週は発動ずみ）" : ""))
            .font(.caption).foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        if let sessionId = member.liveSessionId, !isMe {
            Button {
                Task {
                    await live.cheer(sessionId: sessionId, kind: "fire")
                    cheered.insert(member.id)
                    showToast("\(member.displayName)に 応援を おくった！")
                }
            } label: {
                Label(cheered.contains(member.id) ? "応援を送りました" : "戦闘中の\(member.displayName)を応援する",
                      systemImage: "flame.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.gymneePrimary(fullWidth: true))
            .disabled(cheered.contains(member.id))
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == text { toast = nil }
        }
    }

    // MARK: - 招待を受けた

    private func inviteCard(_ partyId: UUID) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("友達のパーティに招待されています", systemImage: "person.2.wave.2")
                .font(.subheadline.bold()).foregroundStyle(.white)
            Text("参加しても、いまのパーティはそのままです。トレーニング1回が、入っているすべてのパーティのボスに1撃ずつ入ります。")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
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
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(Theme.Spacing.md)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Self.accent, lineWidth: 2))
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
}

extension PartyBoss.Reward: Identifiable {
    var id: Date { weekStart }
}

/// 宝箱を開けたときの演出。トロフィー（倒したボス）と報酬を見せる。
struct BossRewardReveal: View {
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
