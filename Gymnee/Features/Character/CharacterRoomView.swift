import SwiftUI
import SwiftData

/// 「育成」タブ＝キャラの部屋。ドット絵のゲーム画面。
///
/// 画面いっぱいが部屋で、自分のキャラがその中を歩き回る。数字とグラフは画面から追い出し、
/// 見たいときだけ下のボタンからシートで開く（＝いつもは「生きている部屋」だけが見えている）。
///
/// **現実だけがエンジン**という原則は変えていない。レベル・進化段階・ステータス・元気は
/// すべて完了ワークアウトから導出し、保存された状態を持たない。
/// アプリ内でできるのは、貯まった元気でキャラを遠征に送り出し、見た目の装備を集めることだけ。
struct CharacterRoomView: View {
    let userId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3

    @Query private var completedWorkouts: [Workout]
    @Query private var records: [PersonalRecord]
    @Query private var runs: [ExpeditionRun]
    @Query private var loadouts: [CharacterLoadout]
    /// 合トレ判定用：フォロー中の人の投稿（自分以外）。
    @Query private var feedItems: [FeedItem]

    /// 受け取り演出中の戦利品（道中の出来事つき）。
    @State private var celebrating: ClaimResult?
    @State private var sheet: SheetRoute?
    /// キャラのひとこと。タップ or 一定時間で切り替わる。
    @State private var chatter: CharacterChatter.Line?
    /// シーンの再生開始時刻。画面を離れている間はアニメーションを進めない。
    @State private var startedAt = Date.now

    /// 重い集計をアニメーションのたびに走らせないため、記録が変わったときだけ作り直す。
    @State private var derived = Derived.empty

    init(userId: UUID) {
        self.userId = userId
        _completedWorkouts = Query(filter: #Predicate<Workout> { $0.userId == userId && $0.completedAt != nil })
        _records = Query(filter: #Predicate<PersonalRecord> { $0.userId == userId })
        _runs = Query(
            filter: #Predicate<ExpeditionRun> { $0.userId == userId },
            sort: [SortDescriptor(\ExpeditionRun.startedAt, order: .reverse)]
        )
        _loadouts = Query(filter: #Predicate<CharacterLoadout> { $0.userId == userId })
        _feedItems = Query(filter: #Predicate<FeedItem> { $0.userId != userId })
    }

    /// 受け取り結果（祝福シートに渡す）。
    struct ClaimResult: Identifiable {
        let item: Expedition.Item
        let events: [ExpeditionJourney.Event]
        let coop: Bool
        var id: String { item.id }
    }

    enum SheetRoute: String, Identifiable {
        case status, expedition, outfit, skins, collection, coach
        var id: String { rawValue }
    }

    // MARK: - 導出（すべて現実の記録から）

    /// 画面が要る値をひとまとめにして 1 回で作る。
    struct Derived {
        var level = CharacterProgress.Level(value: 1, expIntoLevel: 0, expForNextLevel: 200)
        var stage = CharacterProgress.Stage.rookie
        var nextStage: CharacterProgress.NextStage?
        var stats: [CharacterProgress.Axis: Int] = [:]
        var build = CharacterBuild(girth: .slim, arm: .thin, leg: .thin)
        var energy = 0
        var weeklyDone = 0
        var streakWeeks = 0
        var sessionCount = 0
        var recordedToday = false
        var daysSinceLastWorkout: Int?

        static let empty = Derived()
    }

    /// 進行中または受け取り待ちの遠征（同時に 1 本まで）。
    private var activeRun: ExpeditionRun? {
        runs.first { !$0.isClaimed }
    }

    /// 受け取り済みの戦利品（新しい順）。
    private var collection: [(run: ExpeditionRun, item: Expedition.Item)] {
        runs.compactMap { run in run.reward.map { (run, $0) } }
    }

    private var ownedItemIds: Set<String> {
        Set(runs.compactMap(\.rewardItemId))
    }

    private var loadout: CharacterLoadout? { loadouts.first }

    private var skin: CharacterSkin { SkinCatalog.skin(id: loadout?.skinId) }

    private var equipped: [Expedition.Slot: Expedition.Item] {
        CharacterOutfit.resolve(loadout: loadout?.loadout ?? [:], owned: ownedItemIds)
    }

    /// 今日いっしょに記録した仲間（合トレ）。フォロー中の人の今日の投稿から拾う。
    private var coopPartners: [CoopDetector.Partner] {
        CoopDetector.partners(feedItems: feedItems)
    }

    /// 集計のやり直しが要るかを判定する軽い指紋。@Query の中身が変わったときだけ変化する。
    private var signature: String {
        "\(completedWorkouts.count)-\(records.count)-\(runs.count)-\(loadouts.first?.updatedAt.timeIntervalSince1970 ?? 0)"
    }

    // MARK: - 画面

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                scene(in: geometry.size)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            refresh()
            startedAt = .now
            // 用事があれば、開いてすぐコーチが歩いて入ってくる。
            updateCoachPresence()
        }
        .onChange(of: signature) { _, _ in
            refresh()
            updateCoachPresence()
        }
        .onChange(of: scenePhase) { _, phase in
            // バックグラウンドから戻ったら時間を巻き戻さない（歩いている途中から続く）。
            if phase == .active {
                refresh()
                updateCoachPresence()
            }
        }
        // 出入りの歩きが終わったかを見るだけの軽いタイマー。毎フレームは要らない。
        .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { now in
            advanceCoachTransition(now: now)
        }
        .sheet(item: $celebrating) { result in
            RewardCelebrationView(result: result)
        }
        .sheet(item: $sheet) { route in
            sheetContent(route)
        }
    }

    @ViewBuilder
    private func scene(in size: CGSize) -> some View {
        // 1 ドットの一辺。画面幅を基準に決め、部屋とキャラで必ず同じ値を使う。
        // 分母を小さくするほどドットが粗く（＝キャラが大きく）なる。
        let dot = max(3, (size.width / 84).rounded())
        let horizon: CGFloat = 0.42
        let floorTop = size.height * horizon
        let floorBottom = size.height - hudHeight

        ZStack(alignment: .bottom) {
            RoomBackdrop(
                timeOfDay: CharacterScene.timeOfDay(at: .now),
                stage: derived.stage,
                shelfItems: collection.map(\.item),
                horizon: horizon,
                dot: dot
            )
            .frame(width: size.width, height: size.height)

            actors(in: size, dot: dot, floorTop: floorTop, floorBottom: floorBottom)

            if let run = activeRun, run.isAwaitingClaim(asOf: .now) {
                treasureChest(in: size, dot: dot, floorTop: floorTop, floorBottom: floorBottom, run: run)
            }

            // ふきだしはアニメーション層の外に出す。中に入れるとタップを受け取れず、
            // 「記録をはじめる」「遠征へ」の導線が死ぬ。
            //
            // 喋るのは**コーチ**であって自分のキャラではない。自分のアバターが自分に
            // 「あと1回で今週の目標」と言うのは筋が通らないので、ふきだしはコーチの頭上に置く。
            // コーチが立っている間だけふきだしを出す。歩いている最中に喋らせると読めない。
            if coachPhase == .present, let line = chatter {
                SpeechBubble(text: line.text) { openCoach() }
                    .frame(maxWidth: size.width * 0.64, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, size.width * Self.coachSpot.x)
                    .padding(.top, coachBubbleTop(in: size, floorTop: floorTop, floorBottom: floorBottom))
                    .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
            }

            // コーチ本体のタップ受け口（Canvas は当たり判定を持たないので矩形を重ねる）。
            if coachPhase == .present {
                Color.clear
                    .frame(width: size.width * 0.22, height: size.height * 0.16)
                    .contentShape(Rectangle())
                    .onTapGesture { openCoach() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, max(0, size.width * Self.coachSpot.x - size.width * 0.11))
                    .padding(.top, coachBubbleTop(in: size, floorTop: floorTop, floorBottom: floorBottom) + 56)
                    .accessibilityLabel("コーチに相談する")
            }

            hud(size: size)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            handleSceneTap(at: location, size: size, floorTop: floorTop, floorBottom: floorBottom)
        }
    }

    /// 画面のタップ。キャラに当たっていれば反応させ、外していればコーチに喋ってもらう。
    private func handleSceneTap(at location: CGPoint, size: CGSize, floorTop: CGFloat, floorBottom: CGFloat) {
        let dot = max(3, (size.width / 84).rounded())
        let pose = CharacterScene.pose(at: Date.now.timeIntervalSince(startedAt), seed: selfSeed)
        let scaled = max(2, (dot * CGFloat(CharacterScene.depthScale(pose.position.y))).rounded())
        let feet = CGPoint(
            x: size.width * CGFloat(pose.position.x),
            y: floorTop + (floorBottom - floorTop) * CGFloat(pose.position.y)
        )
        let side = CGFloat(PixelCharacterArt.canvasHeight) * scaled

        if CharacterReaction.isHit(tap: location, feet: feet, size: side) {
            tapCount += 1
            reactionParticle = CharacterReaction.Particle.next(count: tapCount)
            reactedAt = .now
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            speak()
        }
    }

    /// コーチの立ち位置（歩き回らず、部屋の決まった場所にいる）。
    /// 話しかける相手がいつも同じ場所にいることで、ふきだしの主が誰なのかが迷いなく伝わる。
    private static let coachSpot = CGPoint(x: 0.23, y: 0.14)

    /// コーチ機能そのもののオン/オフ。
    /// #79 で「全部おまかせ / 提案だけ / オフ」の 3 択が入る予定で、**オフではコーチは一切現れない**。
    /// その設定がまだ無いので既定で有効にし、切り替え口だけここに用意しておく。
    @AppStorage("gymnee.coachMode") private var coachMode = "auto"
    private var coachEnabled: Bool { coachMode != "off" }

    /// 同じ用事で見送った記録（クールダウン用）。端末ローカルで十分な情報。
    @AppStorage("gymnee.coachDismissedTopic") private var dismissedTopicRaw = ""
    @AppStorage("gymnee.coachDismissedAt") private var dismissedAt: Double = 0

    /// コーチの出入りの段階と、その段階に入った時刻。
    @State private var coachPhase = CoachVisit.Phase.away
    @State private var coachPhaseSince = Date.now

    /// キャラをタップした時刻と、そのとき浮かべる絵。
    @State private var reactedAt: Date?
    @State private var reactionParticle = CharacterReaction.Particle.heart
    @State private var tapCount = 0

    /// キャラたち。**全員を 1 枚の Canvas に描く**ことで、毎フレームの View 差分を発生させない。
    private func actors(in size: CGSize, dot: CGFloat, floorTop: CGFloat, floorBottom: CGFloat) -> some View {
        let look = PixelCharacterRenderer.Look(
            build: derived.build,
            skin: skin,
            equipped: equipped,
            stage: derived.stage,
            carriesPack: activeRun?.isInProgress(asOf: .now) ?? false,
            nameTag: nil
        )
        let partners = Array(coopPartners.prefix(3))
        let started = startedAt

        return TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let elapsed = timeline.date.timeIntervalSince(started)

                // 奥にいる者から描く（手前が上に重なる）。
                var cast: [(pose: CharacterScene.Pose, look: PixelCharacterRenderer.Look)] = []

                // 自分のキャラ。タップされた直後は反応の仕草に差し替える（位置と向きは保つ）。
                var selfPose = CharacterScene.pose(at: elapsed, seed: selfSeed)
                let reactionElapsed = reactedAt.map { timeline.date.timeIntervalSince($0) }
                if let reactionElapsed,
                   let reacting = CharacterReaction.pose(base: selfPose, elapsed: reactionElapsed) {
                    selfPose = reacting
                }
                cast.append((selfPose, look))

                // コーチ。用事があるときだけ歩いて入ってきて、済んだら歩いて帰る。
                if let coachPose = CoachVisit.pose(
                    phase: coachPhase,
                    elapsed: timeline.date.timeIntervalSince(coachPhaseSince),
                    spot: Self.coachSpot
                ) {
                    cast.append((
                        coachPose,
                        PixelCharacterRenderer.Look(
                            build: PixelCharacterRenderer.coachBuild,
                            skin: PixelCharacterRenderer.coachSkin,
                            equipped: [:],
                            stage: .rookie,
                            carriesPack: false,
                            nameTag: nil,
                            role: .coach
                        )
                    ))
                }
                for partner in partners {
                    // 仲間ごとに別のシードと時間差を与えて、同じ動きが揃わないようにする。
                    let seed = DeterministicRandom.seed(from: partner.id)
                    let offset = Double(seed % 40)
                    var partnerLook = look
                    partnerLook.skin = SkinCatalog.all[Int(seed % UInt64(SkinCatalog.all.count))]
                    partnerLook.equipped = [:]
                    partnerLook.carriesPack = false
                    partnerLook.nameTag = partner.name
                    cast.append((CharacterScene.pose(at: elapsed + offset, seed: seed), partnerLook))
                }

                for member in cast.sorted(by: { $0.pose.position.y < $1.pose.position.y }) {
                    let pose = member.pose
                    let frame = PixelCharacterLayout.frame(for: pose)
                    let feet = CGPoint(
                        x: size.width * CGFloat(pose.position.x),
                        y: floorTop + (floorBottom - floorTop) * CGFloat(pose.position.y)
                    )
                    // 奥行きでドットの大きさを変える。整数倍に丸めてドットの格子を崩さない。
                    let scaled = max(2, (dot * CGFloat(CharacterScene.depthScale(pose.position.y))).rounded())
                    PixelCharacterRenderer.draw(
                        in: &context, look: member.look, frame: frame,
                        facing: pose.facing, feet: feet, dot: scaled
                    )
                }

                // タップの返事。自分のキャラの頭上に、ハートや音符をふわっと浮かせる。
                if let reactionElapsed,
                   let progress = CharacterReaction.particleProgress(elapsed: reactionElapsed) {
                    let scaled = max(2, (dot * CGFloat(CharacterScene.depthScale(selfPose.position.y))).rounded())
                    let side = CGFloat(PixelCharacterArt.canvasHeight) * scaled
                    let feet = CGPoint(
                        x: size.width * CGFloat(selfPose.position.x),
                        y: floorTop + (floorBottom - floorTop) * CGFloat(selfPose.position.y)
                    )
                    var palette = PixelPalette.neutral
                    palette.accent = reactionParticle == .heart ? Color(hexF: 0xFF7B9C) : Theme.limeFill
                    let sprite = reactionSprite
                    context.drawPixels(
                        sprite,
                        at: CGPoint(
                            x: (feet.x + side * 0.22).rounded(),
                            y: (feet.y - side - side * CGFloat(CharacterReaction.particleRise(progress: progress))).rounded()
                        ),
                        dot: scaled,
                        palette: palette,
                        opacity: CharacterReaction.particleOpacity(progress: progress)
                    )
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .frame(width: size.width, height: size.height)
    }

    /// 自分のキャラの歩き方を決めるシード。人によって歩き回り方が変わる。
    private var selfSeed: UInt64 { DeterministicRandom.seed(from: userId) }

    private var reactionSprite: PixelSprite {
        switch reactionParticle {
        case .heart: return PixelCharacterArt.heart
        case .note: return PixelCharacterArt.note
        case .sparkle: return PixelCharacterArt.sparkle
        }
    }

    /// コーチのふきだしを置く高さ（コーチの頭より少し上）。
    private func coachBubbleTop(in size: CGSize, floorTop: CGFloat, floorBottom: CGFloat) -> CGFloat {
        let dot = max(3, (size.width / 84).rounded())
        let scaled = max(2, (dot * CGFloat(CharacterScene.depthScale(Self.coachSpot.y))).rounded())
        let feetY = floorTop + (floorBottom - floorTop) * CGFloat(Self.coachSpot.y)
        let headTop = feetY - CGFloat(PixelCharacterArt.canvasHeight) * scaled
        // ふきだしの高さぶん上に逃がす。負にならないよう最低限のマージンを残す。
        return max(size.height * 0.06, headTop - 64)
    }

    // MARK: - 宝箱

    private func treasureChest(in size: CGSize, dot: CGFloat, floorTop: CGFloat, floorBottom: CGFloat, run: ExpeditionRun) -> some View {
        let x = size.width * 0.78
        let y = floorTop + (floorBottom - floorTop) * 0.35
        return TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
            // 跳ねながら蓋がガタつく＝「開けてほしい」を無言で伝える。
            let tick = Int(timeline.date.timeIntervalSince1970 / 0.4)
            let bounce = tick % 2 == 0
            let sprite = PixelCharacterArt.chest(bounce ? 1 : 0)
            Canvas { context, _ in
                context.drawPixels(
                    sprite,
                    at: CGPoint(
                        x: (x - CGFloat(sprite.width) * dot / 2).rounded(),
                        y: (y - CGFloat(sprite.height) * dot - (bounce ? dot : 0)).rounded()
                    ),
                    dot: dot,
                    palette: .neutral
                )
                // 目印のきらめき。床に紛れて見落とされないように。
                if bounce {
                    var palette = PixelPalette.item(rarity: .epic)
                    palette.accent = Theme.lime
                    context.drawPixels(
                        PixelCharacterArt.sparkle,
                        at: CGPoint(
                            x: (x + CGFloat(sprite.width) * dot / 2 - dot).rounded(),
                            y: (y - CGFloat(sprite.height + 4) * dot).rounded()
                        ),
                        dot: dot,
                        palette: palette
                    )
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle().path(in: CGRect(
            x: x - dot * 8, y: y - dot * 10, width: dot * 16, height: dot * 12
        )))
        .onTapGesture { claim(run) }
        .accessibilityLabel("遠征から帰った荷物を受け取る")
    }

    // MARK: - HUD

    private var hudHeight: CGFloat { 132 }

    private func hud(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                levelBadge
                Spacer()
                energyBadge
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)

            Spacer()

            if derived.sessionCount == 0 {
                startPrompt
            } else {
                actionBar
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// HUD の台座。**ライト/ダークに関わらず常に暗い**ので、上に載せる色は明色で固定する。
    /// `Theme.lime` のような可変トークンを載せると、ライトモードでは濃い緑が暗い台座に
    /// 沈んで読めなくなる（実際に「ルーキー」が潰れていた）。
    private static let hudPlate = Color.black.opacity(0.55)
    private static let hudAccent = Color(hexF: 0xC6FF3D)

    private var levelBadge: some View {
        Button { sheet = .status } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: derived.stage.symbol)
                        .font(.caption.bold())
                    Text(derived.stage.title)
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Self.hudAccent)

                Text("Lv.\(derived.level.value)")
                    .font(.numS)
                    .foregroundStyle(.white)

                // EXP バー。
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(Self.hudAccent)
                            .frame(width: proxy.size.width * max(0.02, derived.level.progress))
                    }
                }
                .frame(width: 84, height: 5)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Self.hudPlate, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var energyBadge: some View {
        Button { sheet = .expedition } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "bolt.heart.fill")
                    .font(.caption)
                    .foregroundStyle(Self.hudAccent)
                Text("\(derived.energy)")
                    .font(.numS)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Self.hudPlate, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var actionBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            sceneButton("ステータス", "chart.bar.fill", route: .status)
            sceneButton("遠征", "map.fill", route: .expedition, badge: expeditionBadge)
            sceneButton("着替え", "tshirt.fill", route: .outfit, disabled: ownedItemIds.isEmpty)
            sceneButton("戦利品", "shippingbox.fill", route: .collection, disabled: collection.isEmpty)
            sceneButton("スキン", "paintpalette.fill", route: .skins)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.xl)
    }

    /// 遠征ボタンに出す印。今すぐ触れる用事があるときだけ点ける。
    private var expeditionBadge: Bool {
        if let run = activeRun { return run.isAwaitingClaim(asOf: .now) }
        return derived.energy >= (Expedition.courses.first?.energyCost ?? .max)
    }

    private func sceneButton(_ title: String, _ symbol: String, route: SheetRoute, badge: Bool = false, disabled: Bool = false) -> some View {
        Button { sheet = route } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(disabled ? Color.white.opacity(0.35) : .white)
                        .frame(width: 46, height: 46)
                        .background(Self.hudPlate, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    if badge {
                        Circle()
                            .fill(Self.hudAccent)
                            .frame(width: 10, height: 10)
                            .offset(x: 3, y: -3)
                    }
                }
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(disabled ? Color.white.opacity(0.4) : .white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private var startPrompt: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("キャラが育つのは現実のトレーニングだけ")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Text("1回記録すると、この部屋が動き出す")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Button("記録をはじめる") {
                NotificationCenter.default.post(name: .gymneeStartWorkout, object: nil)
            }
            .buttonStyle(.gymneePrimary)
        }
        .padding(Theme.Spacing.lg)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
    }

    // MARK: - シート

    @ViewBuilder
    private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
        case .status:
            CharacterStatusSheet(
                level: derived.level,
                stage: derived.stage,
                nextStage: derived.nextStage,
                stats: derived.stats,
                streakWeeks: derived.streakWeeks,
                sessionCount: derived.sessionCount
            )
        case .expedition:
            ExpeditionSheet(
                level: derived.level.value,
                availableEnergy: derived.energy,
                activeRun: activeRun,
                coopPartners: coopPartners.map(\.name),
                onStart: start(_:),
                onClaim: claim(_:)
            )
        case .outfit:
            OutfitSheet(owned: ownedItemIds, equipped: equipped) { slot, itemId in
                equip(itemId, in: slot)
            }
        case .skins:
            SkinShopSheet(
                currentSkinId: skin.id,
                purchased: loadout?.purchasedSkins ?? [],
                onSelect: { selectSkin($0) },
                onPurchase: { purchaseSkin($0) }
            )
        case .collection:
            LootCollectionSheet(items: collection.map(\.item))
        case .coach:
            CoachSheet(
                topics: CoachConsultation.topics(for: chatterContext()),
                opening: chatter?.text ?? currentLine().text,
                onAction: { action in
                    sheet = nil
                    perform(action)
                },
                onDismiss: { dismissCoach() }
            )
        }
    }

    // MARK: - 集計

    /// 重い集計をまとめて 1 回で作る。`@Query` の中身が変わったときだけ呼ぶ。
    private func refresh() {
        let sessions = CharacterInputs.sessions(
            from: completedWorkouts,
            prCountByWorkout: CharacterInputs.prCountByWorkout(records)
        )
        let activeDays = completedWorkouts.map { $0.completedAt ?? $0.date }
        let streak = StreakCalculator.currentWeeklyStreak(activeDays: activeDays, weeklyGoal: weeklyGoal)
        let level = CharacterProgress.level(totalExperience: CharacterProgress.totalExperience(sessions: sessions))
        let stats = CharacterProgress.stats(volumeByMuscle: CharacterInputs.volumeByMuscle(from: completedWorkouts))
        let stage = CharacterProgress.stage(
            level: level.value, prCount: records.count, weeklyStreakWeeks: streak.weeks
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let lastWorkout = activeDays.max()

        var next = Derived()
        next.level = level
        next.stage = stage
        next.nextStage = CharacterProgress.nextStage(
            level: level.value, prCount: records.count, weeklyStreakWeeks: streak.weeks
        )
        next.stats = stats
        next.build = CharacterBuild.make(from: CharacterAppearance.make(stats: stats, stage: stage))
        next.energy = Expedition.availableEnergy(
            sessions: sessions, spent: runs.reduce(0) { $0 + $1.energySpent }
        )
        next.streakWeeks = streak.weeks
        next.sessionCount = sessions.count
        next.weeklyDone = activeDays.filter {
            calendar.isDate($0, equalTo: .now, toGranularity: .weekOfYear)
        }.count
        next.recordedToday = activeDays.contains { calendar.isDate($0, inSameDayAs: today) }
        next.daysSinceLastWorkout = lastWorkout.map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: today).day ?? 0
        }
        derived = next
    }

    // MARK: - 操作

    // MARK: - コーチの来訪

    /// 見送った用事（クールダウン判定に使う）。
    private var lastDismissed: (topic: CoachVisit.Topic, at: Date)? {
        guard let topic = CoachVisit.Topic(rawValue: dismissedTopicRaw), dismissedAt > 0 else { return nil }
        return (topic, Date(timeIntervalSince1970: dismissedAt))
    }

    /// いまコーチに来てもらう用事があるか。
    private var pendingTopic: CoachVisit.Topic? {
        guard coachEnabled else { return nil }
        return CoachVisit.Topic(action: currentLine().action)
    }

    /// 来訪の要否を判定して段階を進める。画面表示時と、記録・遠征が変わったときに呼ぶ。
    private func updateCoachPresence() {
        let shouldVisit = CoachVisit.shouldVisit(topic: pendingTopic, lastDismissed: lastDismissed)
        switch coachPhase {
        case .away where shouldVisit:
            setCoachPhase(.arriving)
            chatter = currentLine()
        case .present where !shouldVisit:
            setCoachPhase(.leaving)
        case .arriving where !shouldVisit:
            setCoachPhase(.leaving)
        default:
            break
        }
    }

    /// 歩き終わりを見て、次の段階へ送る。
    private func advanceCoachTransition(now: Date) {
        let elapsed = now.timeIntervalSince(coachPhaseSince)
        guard CoachVisit.isTransitionFinished(elapsed: elapsed) else { return }
        switch coachPhase {
        case .arriving: setCoachPhase(.present)
        case .leaving: setCoachPhase(.away)
        case .away, .present: break
        }
    }

    private func setCoachPhase(_ phase: CoachVisit.Phase) {
        guard coachPhase != phase else { return }
        coachPhase = phase
        coachPhaseSince = .now
        if phase == .away || phase == .leaving {
            withAnimation(.snappy) { chatter = nil }
        }
    }

    /// 用事を見送る。同じ用事では一定時間戻ってこない。
    private func dismissCoach() {
        if let topic = pendingTopic {
            dismissedTopicRaw = topic.rawValue
            dismissedAt = Date.now.timeIntervalSince1970
        }
        setCoachPhase(.leaving)
    }

    private func openCoach() {
        sheet = .coach
    }

    // MARK: - セリフ

    /// いまの状況をコーチの材料にまとめる。
    private func chatterContext() -> CharacterChatter.Context {
        let expeditionState: CharacterChatter.ExpeditionState
        if let run = activeRun {
            expeditionState = run.isAwaitingClaim(asOf: .now)
                ? .awaitingClaim
                : .running(remaining: Expedition.remainingText(finishesAt: run.finishesAt, now: .now))
        } else {
            expeditionState = .idle
        }
        return CharacterChatter.Context(
            recordedToday: derived.recordedToday,
            weeklyDone: derived.weeklyDone,
            weeklyGoal: weeklyGoal,
            streakWeeks: derived.streakWeeks,
            energy: derived.energy,
            cheapestCourseCost: Expedition.unlockedCourses(level: derived.level.value).map(\.energyCost).min(),
            expedition: expeditionState,
            partners: coopPartners.map(\.name),
            nextStageUnmet: derived.nextStage?.unmet ?? [],
            daysSinceLastWorkout: derived.daysSinceLastWorkout
        )
    }

    private func currentLine() -> CharacterChatter.Line {
        CharacterChatter.line(for: chatterContext(), seed: UInt64(Date.now.timeIntervalSince1970))
    }

    /// コーチが立っているときだけ、いまの用事を喋らせる。
    private func speak() {
        guard coachPhase == .present else { return }
        withAnimation(.bouncy) { chatter = currentLine() }
    }

    private func perform(_ action: CharacterChatter.Line.Action?) {
        switch action {
        case .startWorkout:
            NotificationCenter.default.post(name: .gymneeStartWorkout, object: nil)
        case .expedition:
            sheet = .expedition
        case .claim:
            if let run = activeRun { claim(run) }
        case nil:
            break
        }
        // 用事に応じたので、コーチはいったん引き上げる。
        dismissCoach()
    }

    /// 遠征に送り出す。元気は `ExpeditionRun.energySpent` の合計として引かれる。
    private func start(_ course: Expedition.Course) {
        guard activeRun == nil,
              derived.level.value >= course.minLevel,
              derived.energy >= course.energyCost else { return }
        let startedAt = Date.now
        context.insert(
            ExpeditionRun(
                userId: userId,
                courseId: course.id,
                startedAt: startedAt,
                finishesAt: Expedition.finishDate(startedAt: startedAt, course: course),
                energySpent: course.energyCost
            )
        )
        try? context.save()
        sheet = nil
    }

    /// 帰還した遠征の報酬を受け取る。抽選は遠征 id をシードにした決定的抽選。
    /// 空いている部位、または今より良いものが出たときは自動で着せる（持ち帰ったら姿が変わる）。
    private func claim(_ run: ExpeditionRun) {
        guard run.isAwaitingClaim(asOf: .now) else { return }
        let coop = !coopPartners.isEmpty
        let item = Expedition.reward(courseId: run.courseId, seed: run.id, coop: coop)
        run.rewardItemId = item.id
        run.claimedAt = .now

        let state = ensureLoadout()
        if CharacterOutfit.shouldAutoEquip(item, current: equipped[item.slot]) {
            state.setItem(item.id, for: item.slot)
        }
        try? context.save()

        sheet = nil
        celebrating = ClaimResult(
            item: item,
            events: ExpeditionJourney.events(courseId: run.courseId, seed: run.id, coop: coop),
            coop: coop
        )
    }

    private func equip(_ itemId: String?, in slot: Expedition.Slot) {
        let state = ensureLoadout()
        state.setItem(itemId, for: slot)
        try? context.save()
    }

    private func selectSkin(_ id: String) {
        let state = ensureLoadout()
        state.skinId = id
        state.updatedAt = .now
        try? context.save()
    }

    /// スキン購入。**課金は未接続のダミー**で、押した時点で所持扱いにする。
    private func purchaseSkin(_ skin: CharacterSkin) {
        let state = ensureLoadout()
        state.addPurchasedSkin(skin.id)
        state.skinId = skin.id
        try? context.save()
    }

    /// 見た目の保存先を必要になった時に作る。
    private func ensureLoadout() -> CharacterLoadout {
        if let existing = loadout { return existing }
        let created = CharacterLoadout(userId: userId)
        context.insert(created)
        return created
    }
}

// MARK: - ふきだし

/// キャラのひとこと。用事があるものはタップでその画面へ飛ぶ。
private struct SpeechBubble: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.xxl)
    }
}

// MARK: - 受け取り演出

/// 受け取り演出。道中に何が起きたかを見せてから戦利品を渡す（送って待つだけにしないため）。
private struct RewardCelebrationView: View {
    let result: CharacterRoomView.ClaimResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                PixelSpriteView(
                    sprite: PixelItemArt.icon(for: result.item),
                    palette: .item(rarity: result.item.rarity),
                    side: 128
                )
                .padding(Theme.Spacing.lg)
                .background(Theme.limeSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                VStack(spacing: Theme.Spacing.xs) {
                    Text(result.item.rarity.label)
                        .font(.overline)
                        .foregroundStyle(Theme.textTertiary)
                    Text(result.item.name)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(result.item.slot.label)に装備できる")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: result.coop ? "道中（共闘）" : "道中")
                    ForEach(result.events) { event in
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            Image(systemName: event.symbol)
                                .font(.subheadline)
                                .foregroundStyle(event.isGood ? Theme.lime : Theme.textTertiary)
                                .frame(width: 22)
                            Text(event.text)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gymneeCard()

                Button("閉じる") { dismiss() }
                    .buttonStyle(.gymneePrimary(fullWidth: true))
            }
            .padding(Theme.Spacing.xl)
        }
        .background(Theme.bg0)
    }
}
