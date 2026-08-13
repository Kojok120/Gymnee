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
    @Environment(StoreService.self) private var store
    @Environment(AppErrorCenter.self) private var errors
    @AppStorage("gymnee.weeklyGoal") private var weeklyGoal = 3

    @Query private var completedWorkouts: [Workout]
    @Query private var records: [PersonalRecord]
    @Query private var runs: [ExpeditionRun]
    @Query private var loadouts: [CharacterLoadout]
    /// 髪型・アクセサリー（`CharacterLoadout` とは別モデル）。
    @Query private var styles: [CharacterStyle]
    /// 今日のクエスト（コーチが組んだメニュー）。
    @Query private var quests: [PlannedWorkout]
    /// 拾ったグッズ（同じものを二度拾わせないための記録）。
    @Query private var pickups: [RoomPickupRecord]
    /// 合トレ判定用：フォロー中の人の投稿（自分以外）。
    @Query private var feedItems: [FeedItem]
    /// 連れているペット（`CharacterStyle` と同じく別モデル）。
    @Query private var pets: [PetState]

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
        _styles = Query(filter: #Predicate<CharacterStyle> { $0.userId == userId })
        _quests = Query(filter: #Predicate<PlannedWorkout> { $0.userId == userId && !$0.isDone })
        _pickups = Query(filter: #Predicate<RoomPickupRecord> { $0.userId == userId })
        _feedItems = Query(filter: #Predicate<FeedItem> { $0.userId != userId })
        _pets = Query(filter: #Predicate<PetState> { $0.userId == userId })
    }

    /// 受け取り結果（祝福シートに渡す）。
    struct ClaimResult: Identifiable {
        let item: Expedition.Item
        let events: [ExpeditionJourney.Event]
        let coop: Bool
        var id: String { item.id }
    }

    enum SheetRoute: String, Identifiable {
        /// `body` はキャラ本体をタップしたときに開く人体図（旧「分析」タブ）。
        case status, expedition, quest, outfit, skins, collection, coach, body
        var id: String { rawValue }
    }

    // MARK: - 導出（すべて現実の記録から）

    /// 画面が要る値をひとまとめにして 1 回で作る。
    struct Derived {
        var level = CharacterProgress.Level(value: 1, expIntoLevel: 0, expForNextLevel: 200)
        /// 累積 EXP。完了直後の祝いで「この1回で実際に増えた分」を出すのに使う。
        var totalExperience = 0
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
        /// 前週の記録から決まるグッズの落下倍率。
        var dropMultiplier: Double = 1

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

    /// いま着ている見た目。**所持で解決してから描く**。
    /// 返金・失効・ファミリー共有の解除で所持が消えたら既定へ落ちるので、
    /// 持っていないスキンや髪型を描き続けることがない（`CharacterOutfit.resolve` と同じ考え方）。
    private var skin: CharacterSkin {
        SkinCatalog.resolve(selected: loadout?.skinId, owned: ownedCosmeticIds)
    }

    private var hairStyleId: String {
        PixelHairArt.resolveStyle(selected: style?.hairStyleId, owned: ownedCosmeticIds).id
    }

    private var accessoryId: String {
        PixelHairArt.resolveAccessory(selected: style?.accessoryId, owned: ownedCosmeticIds).id
    }

    private var equipped: [Expedition.Slot: Expedition.Item] {
        CharacterOutfit.resolve(loadout: loadout?.loadout ?? [:], owned: ownedItemIds)
    }

    /// 今日いっしょに記録した仲間（合トレ）。フォロー中の人の今日の投稿から拾う。
    private var coopPartners: [CoopDetector.Partner] {
        CoopDetector.partners(feedItems: feedItems)
    }

    /// 集計のやり直しが要るかを判定する軽い指紋。@Query の中身が変わったときだけ変化する。
    private var signature: String {
        "\(completedWorkouts.count)-\(records.count)-\(runs.count)-\(pickups.count)-\(loadouts.first?.updatedAt.timeIntervalSince1970 ?? 0)-\(styles.first?.updatedAt.timeIntervalSince1970 ?? 0)"
    }

    // MARK: - 画面

    var body: some View {
        NavigationStack {
            // 外側で safe area の量（＝タブバー + ホームインジケータの高さ）を測ってから、
            // 内側で safe area を無視して全面に描く。部屋（床）はタブバーの下まで広がるが、
            // ボタン類は inset ぶん持ち上げてタブバーに重ねない。
            // 単体ハーネス（タブバー無し）では inset がホームインジケータ分だけになり、両方で正しく出る。
            GeometryReader { outer in
                let bottomInset = outer.safeAreaInsets.bottom
                GeometryReader { geometry in
                    scene(in: geometry.size, bottomInset: bottomInset)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            refresh()
            // 集計を作り直したあとで見る（差分の「後」は derived を使う）。
            takePendingCelebration()
            startedAt = .now
            // 用事があれば、開いてすぐコーチが歩いて入ってくる。
            updateCoachPresence()
            // 遊び方はこの部屋では説明されないので、初回だけ案内を出す。
            if !hasSeenOnboarding {
                showOnboarding = true
                hasSeenOnboarding = true
            }
        }
        .onChange(of: signature) { _, _ in
            refresh()
            // 記録タブで完了 → 育成タブへ、の順で来ると @Query の反映が onAppear より後になる。
            // 記録が増えたこのタイミングでも見て、取りこぼさない。
            takePendingCelebration()
            updateCoachPresence()
        }
        // タブは一度開くと生き続けるので、記録タブが控えを書いた時点では
        // この画面の onAppear が走らないことがある。切替の通知でも見る。
        .onReceive(NotificationCenter.default.publisher(for: .gymneeShowCharacter)) { _ in
            takePendingCelebration()
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
        // 遠征の帰還は時刻でしか変わらない（@Query は動かない）ので、
        // 一定間隔で用事を見直す。これが無いとセリフと部屋の様子が食い違ったままになる。
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in
            updateCoachPresence()
        }
        .sheet(item: $celebrating) { result in
            RewardCelebrationView(result: result)
        }
        .sheet(item: $celebratingGain) { gain in
            GrowthCelebrationSheet(
                gain: gain,
                look: PixelCharacterRenderer.Look(
                    build: derived.build, skin: skin, equipped: equipped, stage: derived.stage,
                    carriesPack: false, nameTag: nil, role: .trainee,
                    hairStyleId: hairStyleId, accessoryId: accessoryId
                ),
                nextStage: derived.nextStage
            )
        }
        .sheet(item: $sheet) { route in
            sheetContent(route)
        }
        .sheet(isPresented: $showOnboarding) {
            CharacterOnboardingSheet()
        }
    }

    @ViewBuilder
    private func scene(in size: CGSize, bottomInset: CGFloat) -> some View {
        // 1 ドットの一辺。画面幅を基準に決め、部屋とキャラで必ず同じ値を使う。
        // 分母を小さくするほどドットが粗く（＝キャラが大きく）なる。
        let dot = max(3, (size.width / 84).rounded())
        let horizon: CGFloat = 0.42
        let floorTop = size.height * horizon
        // キャラの歩ける下限は HUD とタブバーの上まで（後ろに潜ると拾えない・見えない）。
        let floorBottom = size.height - hudHeight - bottomInset

        ZStack(alignment: .bottom) {
            RoomBackdrop(
                timeOfDay: CharacterScene.timeOfDay(at: .now),
                stage: derived.stage,
                shelfItems: collection.map(\.item),
                horizon: horizon,
                dot: dot,
                doorGlows: canStartExpedition
            )
            .frame(width: size.width, height: size.height)

            actors(in: size, dot: dot, floorTop: floorTop, floorBottom: floorBottom)

            // 落ちているグッズ。キャラより手前に置くと主役が入れ替わるので、床に伏せて描く。
            pickupLayer(in: size, dot: dot, floorTop: floorTop, floorBottom: floorBottom)

            // 留守中の置き手紙。キャラが居ない部屋に「どこへ行ったか」を残す。
            if let run = activeRun, run.isInProgress(asOf: .now), departedAt == nil {
                letterLayer(in: size, dot: dot, floorTop: floorTop, floorBottom: floorBottom, run: run)
            }

            if let run = activeRun, run.isAwaitingClaim(asOf: .now) {
                treasureChest(in: size, dot: dot, floorTop: floorTop, floorBottom: floorBottom, run: run)
            }

            // ドア＝遠征の専用ボタン。シートのボタンを探させず、部屋の中で完結させる。
            doorButton(in: size, dot: dot, floorTop: floorTop)

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

            if let item = collectedToast {
                pickupToast(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, hudHeight + bottomInset + Theme.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if let letterNote {
                letterNoteOverlay(letterNote)
                    .transition(.opacity)
            }

            if showBodyTapHint {
                bodyTapHint
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, hudHeight + bottomInset + Theme.Spacing.lg)
            }

            hud(size: size, bottomInset: bottomInset)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        // 部屋の中身は Canvas でヒットテストを持たず、操作は座標タップに依存している。
        // そのままだと VoiceOver から人体図に一切たどり着けない（分析タブを畳んだので、
        // ここが唯一の入口）。歩き回る相手を座標で追わせず、名前つきの操作として出す。
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "からだの状態を見る") {
            bodyTapHinted = true
            sheet = .body
        }
        .accessibilityActions {
            if activePet != nil {
                Button("ペットを撫でる") { petReaction.fire() }
            }
        }
        // タップとスワイプを 1 つのジェスチャで受ける。
        // スワイプ（Swoop）は指が通った先のグッズを**連続で**拾う。指を離すまでが 1 回の Swoop。
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    swoop(through: value.location, size: size, floorTop: floorTop, floorBottom: floorBottom)
                }
                .onEnded { value in
                    let moved = hypot(value.translation.width, value.translation.height)
                    let collectedAny = !swoopItems.isEmpty
                    endSwoop()
                    // ほぼ動いていない＝タップ。スワイプで何か拾った指離しはタップ扱いにしない。
                    if moved < 12, !collectedAny {
                        handleSceneTap(at: value.location, size: size, floorTop: floorTop, floorBottom: floorBottom)
                    }
                }
        )
    }

    /// 画面のタップ。**手前にいるものから順に**判定する（描画の重なり順と揃える）。
    ///
    /// ペット＝撫でると喜ぶ、自分のキャラ＝「からだ」（人体図）を開く、外れ＝コーチが喋る。
    /// 分身をタップして自分のからだの状態を見る、という結びつきで人体図を出し、
    /// かわいい反応（ハート・音符・きらめき）はペットの役目にした。
    private func handleSceneTap(at location: CGPoint, size: CGSize, floorTop: CGFloat, floorBottom: CGFloat) {
        let dot = max(3, (size.width / 84).rounded())
        let elapsed = Date.now.timeIntervalSince(startedAt)
        let isAway = activeRun?.isInProgress(asOf: .now) ?? false

        func feet(_ position: CGPoint) -> CGPoint {
            CGPoint(
                x: size.width * CGFloat(position.x),
                y: floorTop + (floorBottom - floorTop) * CGFloat(position.y)
            )
        }
        func scaled(_ y: Double) -> CGFloat {
            max(2, (dot * CGFloat(CharacterScene.depthScale(y))).rounded())
        }

        let charPose = CharacterScene.pose(at: elapsed, seed: selfSeed)
        let petPose = activePet.map {
            PetScene.pose(at: elapsed, ownerSeed: selfSeed, seed: petSeed($0.id), ownerAway: isAway)
        }

        // ペットのほうが小さく、飼い主に重なることもあるので先に見る。
        if let petPose, activePet != nil {
            let side = CGFloat(PixelPetArt.canvasHeight) * scaled(Double(petPose.position.y))
            if TapReaction.isHit(tap: location, feet: feet(petPose.position), size: side,
                                 radiusRatio: TapReaction.petHitRadiusRatio) {
                petReaction.fire()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
        }

        let side = CGFloat(PixelCharacterArt.canvasHeight) * scaled(Double(charPose.position.y))
        if !isAway, TapReaction.isHit(tap: location, feet: feet(charPose.position), size: side) {
            // 押せたことが分かるよう触覚だけ返し、そのままシートを開く。
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            bodyTapHinted = true
            sheet = .body
            return
        }

        speak()
    }

    /// からだのヒントを出すか。キャラが遠征で不在のときは押す相手がいないので出さない。
    private var showBodyTapHint: Bool {
        guard !bodyTapHinted, bodyHintVisible, sheet == nil else { return false }
        return !(activeRun?.isInProgress(asOf: .now) ?? false)
    }

    /// 「キャラを押すとからだが見られる」の一度きりの案内。
    /// 図の上に重ねる `AnalyticsView` のヒントと同じ作りにして、押し方の説明は同じ見た目で統一する。
    private var bodyTapHint: some View {
        Label("キャラをタップすると、からだの状態が見られる", systemImage: "hand.tap.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.bg1)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.textPrimary.opacity(0.88), in: Capsule())
            .allowsHitTesting(false)
            .transition(.opacity)
            .task {
                // 気づかれないまま出し続けない。押されたら AppStorage 側で恒久的に消える。
                try? await Task.sleep(for: .seconds(8))
                // `.task` はビューが消えると**キャンセルされるが sleep は例外を飲む**ので、
                // ここで確認しないと「8秒待った」と同じ扱いで消してしまう。
                // 案内が出て数秒でシートを開いただけで、そのセッション中は二度と出なくなる。
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { bodyHintVisible = false }
            }
    }

    /// コーチの立ち位置（歩き回らず、部屋の決まった場所にいる）。
    /// 話しかける相手がいつも同じ場所にいることで、ふきだしの主が誰なのかが迷いなく伝わる。
    private static let coachSpot = CGPoint(x: 0.23, y: 0.14)

    /// コーチの関わり方（設定の 3 択）。**オフではコーチは一切現れない**。
    @AppStorage(CoachMode.storageKey) private var coachModeRaw = CoachMode.default.rawValue
    private var coachMode: CoachMode { CoachMode(rawValue: coachModeRaw) ?? .default }
    private var coachEnabled: Bool { coachMode.showsCoach }

    /// 同じ用事で見送った記録（クールダウン用）。端末ローカルで十分な情報。
    @AppStorage("gymnee.coachDismissedTopic") private var dismissedTopicRaw = ""
    @AppStorage("gymnee.coachDismissedAt") private var dismissedAt: Double = 0

    /// コーチの出入りの段階と、その段階に入った時刻。
    @State private var coachPhase = CoachVisit.Phase.away
    @State private var coachPhaseSince = Date.now

    /// ペットを撫でた反応（対象ごとに 1 つ持つ）。
    @State private var petReaction = TapReaction.State()

    /// 記録を終えた直後に出す「この 1 回で何が育ったか」。
    /// 記録タブが完了処理の前の状態を保存し、育成タブに来たときに消費する。
    @State private var celebratingGain: WorkoutGrowth.Gain?

    /// 「キャラを押すとからだが見られる」を一度だけ伝えるヒント。
    /// 初回案内シートは既に見た人には二度と出ないので、部屋の中でも一度だけ出して取りこぼさない。
    @AppStorage("gymnee.character.bodyTapHinted") private var bodyTapHinted = false
    /// 押されないまま出しっぱなしにしない（数秒で引っ込める）。
    @State private var bodyHintVisible = true

    /// 拾った直後に出す告知。
    @State private var collectedToast: RoomPickup.Item?
    /// 開いた置き手紙の文面（nil＝閉じている）。
    @State private var letterNote: String?
    /// いまの Swoop（1 回のスライド）で拾ったもの。指を離したときにまとめて告知する。
    @State private var swoopItems: [RoomPickup.Item] = []

    /// 遠征に送り出した時刻。ここから数秒だけ「ドアへ歩いて出ていく」演出を出す。
    @State private var departedAt: Date?
    /// 初回案内をまだ見ていないか。
    @AppStorage(CharacterOnboardingSheet.hasSeenKey) private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    /// キャラたち。**全員を 1 枚の Canvas に描く**ことで、毎フレームの View 差分を発生させない。
    private func actors(in size: CGSize, dot: CGFloat, floorTop: CGFloat, floorBottom: CGFloat) -> some View {
        let look = PixelCharacterRenderer.Look(
            build: derived.build,
            skin: skin,
            equipped: equipped,
            stage: derived.stage,
            carriesPack: activeRun?.isInProgress(asOf: .now) ?? false,
            nameTag: nil,
            role: .trainee,
            hairStyleId: hairStyleId,
            accessoryId: accessoryId
        )
        let partners = Array(coopPartners.prefix(3))
        let started = startedAt

        let pet = activePet
        return TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let elapsed = timeline.date.timeIntervalSince(started)

                // 奥にいる者から描く（手前が上に重なる）。人とペットを同じ列に混ぜて
                // y でまとめて並べ替える。別の Canvas に分けると前後関係が壊れる。
                var cast: [RoomActor] = []

                // 自分のキャラ。
                // 遠征に出ている間は部屋にいない（不在そのものが「遠征中」の表示）。
                // 送り出した直後だけ、ドアへ歩いて出ていく演出を挟む。
                var selfPose = CharacterScene.pose(at: elapsed, seed: selfSeed)

                let isAway = activeRun?.isInProgress(asOf: timeline.date) ?? false
                let departing = departedAt.flatMap {
                    ExpeditionDeparture.pose(from: selfPose.position, elapsed: timeline.date.timeIntervalSince($0))
                }
                if let departing {
                    // 出発中はグッズを抱えていく。
                    var leaving = look
                    leaving.carriesPack = true
                    cast.append(.person(departing, leaving))
                    selfPose = departing
                } else if !isAway {
                    cast.append(.person(selfPose, look))
                }

                // コーチ。用事があるときだけ歩いて入ってきて、済んだら歩いて帰る。
                if let coachPose = CoachVisit.pose(
                    phase: coachPhase,
                    elapsed: timeline.date.timeIntervalSince(coachPhaseSince),
                    spot: Self.coachSpot
                ) {
                    cast.append(.person(
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
                    cast.append(.person(CharacterScene.pose(at: elapsed + offset, seed: seed), partnerLook))
                }

                // ペット。飼い主の少し後ろについて回る（遠征中はドアの近くで留守番）。
                if let pet {
                    var petPose = PetScene.pose(
                        at: elapsed, ownerSeed: selfSeed,
                        seed: petSeed(pet.id), ownerAway: isAway
                    )
                    if let elapsedSinceTap = petReaction.elapsed(timeline.date),
                       let reacting = PetScene.reactingPose(base: petPose, elapsed: elapsedSinceTap) {
                        petPose = reacting
                    }
                    cast.append(.pet(petPose, pet))
                }

                for member in cast.sorted(by: { $0.depth < $1.depth }) {
                    let feet = CGPoint(
                        x: size.width * CGFloat(member.position.x),
                        y: floorTop + (floorBottom - floorTop) * CGFloat(member.position.y)
                    )
                    // 奥行きでドットの大きさを変える。整数倍に丸めてドットの格子を崩さない。
                    let scaled = max(2, (dot * CGFloat(CharacterScene.depthScale(member.depth))).rounded())
                    switch member {
                    case .person(let pose, let look):
                        PixelCharacterRenderer.draw(
                            in: &context, look: look, frame: PixelCharacterLayout.frame(for: pose),
                            facing: pose.facing, feet: feet, dot: scaled
                        )
                    case .pet(let pose, let pet):
                        drawPet(in: &context, pose: pose, pet: pet, feet: feet, dot: scaled)
                    }
                }

                // 出発中に抱えているグッズ。
                if let departing, let run = activeRun {
                    let scaled = max(2, (dot * CGFloat(CharacterScene.depthScale(departing.position.y))).rounded())
                    let sprite = carriedSprite(for: run)
                    let feet = CGPoint(
                        x: size.width * CGFloat(departing.position.x),
                        y: floorTop + (floorBottom - floorTop) * CGFloat(departing.position.y)
                    )
                    context.drawPixels(
                        sprite,
                        at: CGPoint(
                            x: (feet.x + scaled * 5).rounded(),
                            y: (feet.y - scaled * 13).rounded()
                        ),
                        dot: scaled,
                        palette: .neutral
                    )
                }

                // 撫でた返事。ペットの頭上に、ハートや音符をふわっと浮かせる。
                if let pet,
                   let elapsedSinceTap = petReaction.elapsed(timeline.date),
                   let progress = TapReaction.particleProgress(elapsed: elapsedSinceTap) {
                    let petPose = PetScene.pose(
                        at: elapsed, ownerSeed: selfSeed,
                        seed: petSeed(pet.id), ownerAway: isAway
                    )
                    let scaled = max(2, (dot * CGFloat(CharacterScene.depthScale(petPose.position.y))).rounded())
                    let side = CGFloat(PixelPetArt.canvasHeight) * scaled
                    let feet = CGPoint(
                        x: size.width * CGFloat(petPose.position.x),
                        y: floorTop + (floorBottom - floorTop) * CGFloat(petPose.position.y)
                    )
                    var palette = PixelPalette.neutral
                    palette.accent = petReaction.particle == .heart ? Color(hexF: 0xFF7B9C) : Theme.limeFill
                    context.drawPixels(
                        Self.particleSprite(petReaction.particle),
                        at: CGPoint(
                            x: (feet.x + side * 0.30).rounded(),
                            y: (feet.y - side - side * CGFloat(TapReaction.particleRise(progress: progress))).rounded()
                        ),
                        dot: scaled,
                        palette: palette,
                        opacity: TapReaction.particleOpacity(progress: progress)
                    )
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .frame(width: size.width, height: size.height)
    }

    /// 部屋に立つもの。人とペットを 1 本の列に混ぜて、y でまとめて前後を決めるための入れ物。
    private enum RoomActor {
        case person(CharacterScene.Pose, PixelCharacterRenderer.Look)
        case pet(PetScene.Pose, PetCatalog.Pet)

        /// 並べ替えと拡大率に使う奥行き（0＝奥 / 1＝手前）。
        var depth: Double {
            switch self {
            case .person(let pose, _): return Double(pose.position.y)
            case .pet(let pose, _): return Double(pose.position.y)
            }
        }

        var position: CGPoint {
            switch self {
            case .person(let pose, _): return pose.position
            case .pet(let pose, _): return pose.position
            }
        }
    }

    /// 自分のキャラの歩き方を決めるシード。人によって歩き回り方が変わる。
    private var selfSeed: UInt64 { DeterministicRandom.seed(from: userId) }

    /// ペット個体のシード。飼い主とずらして、まばたきや立ち位置が同期しないようにする。
    private func petSeed(_ petId: String) -> UInt64 {
        selfSeed &+ DeterministicRandom.seed(from: petId)
    }

    /// いま連れているペット。所持していないものは描かない（返金・失効で壊れた見た目を出さない）。
    private var activePet: PetCatalog.Pet? {
        PetCatalog.resolve(selected: pets.first?.petId, owned: ownedPetIds)
    }

    /// 所持しているペット。ペットにはレガシー付与が無い（1.4.1 で新設したため）ので StoreKit だけを見る。
    private var ownedPetIds: Set<String> {
        Set(PetCatalog.all.map(\.id).filter { isOwned(.pet, $0) })
    }

    /// ペット 1 匹を描く。歩きの弾みは整数ドットで上下させ、ドットの格子を崩さない。
    private func drawPet(
        in context: inout GraphicsContext,
        pose: PetScene.Pose,
        pet: PetCatalog.Pet,
        feet: CGPoint,
        dot: CGFloat
    ) {
        let sprite = PixelPetArt.sprite(petId: pet.id, facing: pose.facing, blink: pose.blink)
        let origin = CGPoint(
            x: (feet.x - CGFloat(PixelPetArt.canvasWidth) * dot / 2).rounded(),
            y: (feet.y - CGFloat(PixelPetArt.canvasHeight) * dot - CGFloat(pose.bob) * dot).rounded()
        )
        context.drawPixels(
            sprite, at: origin, dot: dot,
            palette: PixelPetArt.palette(petId: pet.id),
            flipped: pose.facing.isMirrored
        )
    }

    /// 反応で浮かべる絵。
    private static func particleSprite(_ particle: TapReaction.Particle) -> PixelSprite {
        switch particle {
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

    // MARK: - 落ちているグッズ

    /// いま床に落ちているもの。時刻から決定的に導出するので、保存も常駐処理も要らない。
    private var drops: [RoomPickup.Drop] {
        RoomPickup.drops(
            now: .now,
            seed: selfSeed,
            collected: Set(pickups.map(\.storageId)),
            multiplier: derived.dropMultiplier
        )
    }

    @ViewBuilder
    private func pickupLayer(in size: CGSize, dot: CGFloat, floorTop: CGFloat, floorBottom: CGFloat) -> some View {
        ForEach(drops) { drop in
            let scaled = max(2, (dot * CGFloat(CharacterScene.depthScale(drop.position.y))).rounded())
            let center = CGPoint(
                x: size.width * CGFloat(drop.position.x),
                y: floorTop + (floorBottom - floorTop) * CGFloat(drop.position.y)
            )
            // ふわっと上下させて「拾えるもの」だと分かるようにする。
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let bounce = Int(timeline.date.timeIntervalSince1970 / 0.5) % 2 == 0
                Canvas { context, _ in
                    let sprite = PixelItemArt.pickup(id: drop.item.id)
                    context.drawPixels(
                        sprite,
                        at: CGPoint(
                            x: (center.x - CGFloat(sprite.width) * scaled / 2).rounded(),
                            y: (center.y - CGFloat(sprite.height) * scaled - (bounce ? scaled : 0)).rounded()
                        ),
                        dot: scaled,
                        palette: PixelItemArt.pickupPalette(id: drop.item.id)
                    )
                }
                .frame(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height)
            // 回収はシーン全体の Swoop ジェスチャが受ける（個別の当たり判定は持たない）。
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("\(drop.item.name)が落ちている。なぞって拾う")
        }
    }

    /// Swoop。指が通った位置の近くにあるグッズを拾う。ドラッグ中は毎フレーム呼ばれるので軽く保つ。
    private func swoop(through location: CGPoint, size: CGSize, floorTop: CGFloat, floorBottom: CGFloat) {
        let dot = max(3, (size.width / 84).rounded())
        for drop in drops {
            let scaled = max(2, (dot * CGFloat(CharacterScene.depthScale(drop.position.y))).rounded())
            let center = CGPoint(
                x: size.width * CGFloat(drop.position.x),
                y: floorTop + (floorBottom - floorTop) * CGFloat(drop.position.y) - scaled * 6
            )
            guard RoomPickup.isSwooped(finger: location, dropCenter: center, radius: scaled * 11) else { continue }
            collect(drop)
        }
    }

    /// 拾う。拾った事実だけを残し、元気と EXP は次の集計で合流する。
    private func collect(_ drop: RoomPickup.Drop) {
        guard !pickups.contains(where: { $0.storageId == drop.storageId }) else { return }
        context.insert(
            RoomPickupRecord(
                userId: userId,
                storageId: drop.storageId,
                itemId: drop.item.id
            )
        )
        try? context.save()

        // 連続で拾うほど手応えを強くする（Swoop の気持ちよさはここで作る）。
        swoopItems.append(drop.item)
        UIImpactFeedbackGenerator(style: swoopItems.count >= 3 ? .heavy : .medium).impactOccurred()
    }

    /// Swoop の締め。拾った合計をまとめて 1 回だけ告知する（1 個ごとに出すとうるさい）。
    private func endSwoop() {
        defer { swoopItems = [] }
        let summary = RoomPickup.summarize(collected: swoopItems)
        guard summary.count > 0, let last = summary.lastItem else { return }
        let toast = RoomPickup.Item(
            id: last.id,
            name: summary.title,
            rarity: last.rarity,
            energy: summary.energy,
            experience: summary.experience
        )
        withAnimation(.bouncy) { collectedToast = toast }
        // 一定時間で消す（画面を触らせないと消えない告知にしない）。
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { collectedToast = nil }
        }
    }

    // MARK: - ドア（遠征の専用ボタン）

    /// いま遠征に出せるか（ドアを光らせる条件）。
    private var canStartExpedition: Bool {
        guard activeRun == nil else { return false }
        return Expedition.unlockedCourses(level: derived.level.value)
            .contains { derived.energy >= $0.energyCost }
    }

    /// ドアのタップ受け口。絵は `RoomBackdrop` が描いているので、ここは当たり判定だけ。
    private func doorButton(in size: CGSize, dot: CGFloat, floorTop: CGFloat) -> some View {
        let sprite = PixelCharacterArt.door
        let width = CGFloat(sprite.width) * dot
        let height = CGFloat(sprite.height) * dot
        return Color.clear
            .frame(width: max(56, width), height: max(56, height))
            .contentShape(Rectangle())
            .onTapGesture { sheet = .expedition }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, max(0, size.width * ExpeditionDeparture.doorSpot.x - max(56, width) / 2))
            .padding(.top, max(0, floorTop - height))
            .accessibilityLabel(activeRun == nil ? "遠征に出かける" : "遠征の様子を見る")
    }

    // MARK: - 置き手紙

    private func carriedSprite(for run: ExpeditionRun) -> PixelSprite {
        switch ExpeditionDeparture.carriedItemId(seed: run.id) {
        case "kettlebell": return PixelCharacterArt.kettlebell
        case "water-bottle": return PixelCharacterArt.waterBottle
        default: return PixelCharacterArt.dumbbell
        }
    }

    /// 留守中の置き手紙。タップで文面を読む。
    private func letterLayer(
        in size: CGSize, dot: CGFloat, floorTop: CGFloat, floorBottom: CGFloat, run: ExpeditionRun
    ) -> some View {
        let sprite = PixelCharacterArt.letter
        let center = CGPoint(
            x: size.width * ExpeditionDeparture.letterSpot.x,
            y: floorTop + (floorBottom - floorTop) * ExpeditionDeparture.letterSpot.y
        )
        return Canvas { context, _ in
            context.drawPixels(
                sprite,
                at: CGPoint(
                    x: (center.x - CGFloat(sprite.width) * dot / 2).rounded(),
                    y: (center.y - CGFloat(sprite.height) * dot).rounded()
                ),
                dot: dot,
                palette: .neutral
            )
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            // 文面は**タップしたときだけ**読ませる。常時ふきだしで出すと、
            // コーチのふきだしと重なって両方読めなくなる（実機で発覚）。
            Color.clear
                .frame(width: dot * 18, height: dot * 14)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.bouncy) {
                        letterNote = ExpeditionDeparture.letterText(
                            courseTitle: run.course?.title ?? "遠征",
                            remaining: Expedition.remainingText(finishesAt: run.finishesAt, now: .now),
                            seed: run.id
                        )
                    }
                }
                .position(x: center.x, y: center.y - dot * 3)
                .accessibilityLabel("置き手紙を読む")
        }
    }

    /// 開いた置き手紙。画面のどこかを触れば閉じる。
    private func letterNoteOverlay(_ text: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            PixelSpriteView(sprite: PixelCharacterArt.letter, palette: .neutral, side: 60)
            // 手書きの手紙に見せる。日本語で手書き感が出る既定フォントは明朝体なので serif を使う
            // （Chalkboard 等の手書き欧文フォントは日本語グリフを持たず、結局ゴシックに落ちる）。
            Text(text)
                .font(.system(size: 16, design: .serif))
                .tracking(0.5)
                .lineSpacing(4)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("タップして閉じる")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .padding(.horizontal, Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { letterNote = nil } }
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

    private func hud(size: CGSize, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                levelBadge
                Spacer()
                energyBadge
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)

            Spacer()

            // 記録がまだ無くても下部ボタンは必ず出す。
            // 以前は代わりに大きな案内ブロックを出していたが、それが常時居座って
            // ステータス・遠征・見た目に一切たどり着けなくなっていた（実機で発覚）。
            // 記録への促しはコーチのふきだしと初回案内が担う。
            actionBar
        }
        // タブバー（＋ホームインジケータ）の高さぶん持ち上げる。
        // これが無いとボタン列がタブバーの真下に潜る（実機で発覚）。
        .padding(.bottom, bottomInset)
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
            sceneButton("クエスト", "checklist", route: .quest, badge: hasQuestToday)
            sceneButton("着替え", "tshirt.fill", route: .outfit, disabled: ownedItemIds.isEmpty)
            sceneButton("戦利品", "shippingbox.fill", route: .collection, disabled: collection.isEmpty)
            sceneButton("見た目", "paintpalette.fill", route: .skins)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.xl)
    }

    /// 今日のクエストがあるか（下部ボタンの印）。
    private var hasQuestToday: Bool {
        let calendar = Calendar.current
        return quests.contains { calendar.isDate($0.date, inSameDayAs: .now) && !$0.isDone }
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

    /// 拾った内容の告知。何が増えたのかをその場で伝える。
    private func pickupToast(_ item: RoomPickup.Item) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            PixelSpriteView(
                sprite: PixelItemArt.pickup(id: item.id),
                palette: PixelItemArt.pickupPalette(id: item.id),
                side: 28
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text(item.experience > 0
                     ? "テストステロンパワー +\(item.energy) / EXP +\(item.experience)"
                     : "テストステロンパワー +\(item.energy)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Self.hudAccent)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Self.hudPlate, in: Capsule())
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
            AppearanceSheet(
                build: derived.build,
                stage: derived.stage,
                equipped: equipped,
                currentSkinId: skin.id,
                currentHairId: hairStyleId,
                currentAccessoryId: accessoryId,
                currentPetId: pets.first?.petId ?? PetCatalog.noneId,
                isOwned: { kind, id in isOwned(kind, id) },
                priceText: { kind, id in priceText(kind, id) },
                isStoreReachable: store.isStoreAvailable,
                canPurchase: { kind, id in
                    guard let entry = StoreCatalog.entry(kind: kind, contentID: id) else { return false }
                    return store.isPurchasable(entry.productID)
                },
                onSelectSkin: { selectSkin($0) },
                onSelectHair: { selectHair($0) },
                onSelectAccessory: { selectAccessory($0) },
                onSelectPet: { selectPet($0) },
                onPurchase: { kind, id in await purchase(kind, id) },
                onRestore: { await restorePurchases() },
                onAppearReload: { await store.reloadProductsIfNeeded() }
            )
        case .collection:
            LootCollectionSheet(items: collection.map(\.item))
        case .quest:
            QuestSheet(userId: userId) { sheet = .coach }
        case .coach:
            CoachChatView(userId: userId)
        case .body:
            // 自分の分身をタップして自分のからだを見る。旧「分析」タブの中身をそのまま持ってくる。
            // AnalyticsView から開く部位詳細は自前の NavigationStack を持つ自己完結ビューなので、
            // ここでの destination 宣言は要らない。
            NavigationStack {
                AnalyticsView(userId: userId)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("閉じる") { sheet = nil } }
                    }
            }
        }
    }

    // MARK: - 完了直後の祝い

    /// 記録を終えて育成タブに来たら、その 1 回で何が育ったかを出す。
    ///
    /// 「前」は記録タブが**完了処理の前に控えた値**をそのまま使う（`WorkoutGrowth.Pending`）。
    /// ここで「その回を除いた状態」を組み直してはいけない。自己ベストの更新は行を増やさず
    /// 既存の `PersonalRecord.workoutId` を今回の id に付け替えるので、除外すると
    /// 元々あった自己ベストごと消え、起きていないレベルアップや進化を祝ってしまう。
    /// 控えがあれば取り出して祝う。取り出したら消える（毎回開くたびには出さない）。
    ///
    /// 内容は記録タブが完了した時点で確定させて保存している。ここでは組み立て直さない
    /// （`WorkoutGrowth.Pending` 参照）。**ワークアウトを見に行かないので `@Query` の
    /// 反映を待つ必要がなく、タブ切替の直後でも取りこぼさない**。
    private func takePendingCelebration() {
        guard celebratingGain == nil, let pending = WorkoutGrowth.Pending.take() else { return }
        celebratingGain = pending.gain
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
        // 拾ったグッズの分を合流させる（元気は燃料、EXP はレアのみ）。
        let collectedIds = pickups.map(\.itemId)
        let totalExperience = CharacterProgress.totalExperience(
            sessions: sessions,
            pickupBonus: RoomPickup.totalExperience(collectedItemIds: collectedIds)
        )
        let level = CharacterProgress.level(totalExperience: totalExperience)
        let stats = CharacterProgress.stats(volumeByMuscle: CharacterInputs.volumeByMuscle(from: completedWorkouts))
        let stage = CharacterProgress.stage(
            level: level.value, prCount: records.count, weeklyStreakWeeks: streak.weeks
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let lastWorkout = activeDays.max()

        var next = Derived()
        next.level = level
        next.totalExperience = totalExperience
        next.stage = stage
        next.nextStage = CharacterProgress.nextStage(
            level: level.value, prCount: records.count, weeklyStreakWeeks: streak.weeks
        )
        next.stats = stats
        next.build = CharacterBuild.make(from: CharacterAppearance.make(stats: stats, stage: stage))
        next.energy = Expedition.availableEnergy(
            sessions: sessions,
            spent: runs.reduce(0) { $0 + $1.energySpent },
            bonus: RoomPickup.totalEnergy(collectedItemIds: collectedIds)
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
        // 前の週にどれだけ通ったかで、今週の落下率が決まる。
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: .now) ?? .now
        let lastWeekCount = activeDays.filter {
            calendar.isDate($0, equalTo: lastWeek, toGranularity: .weekOfYear)
        }.count
        next.dropMultiplier = RoomPickup.multiplier(lastWeekCount: lastWeekCount, weeklyGoal: weeklyGoal)
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
        case .present:
            // 立っている間に状況が変わることがある（遠征が帰ってきた等）。
            // 古いセリフを出しっぱなしにすると、部屋の様子と食い違う。
            let fresh = currentLine()
            if chatter?.action != fresh.action { chatter = fresh }
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
        // シートを閉じてから、ドアへ歩いて出ていく演出を始める。
        departedAt = .now
        Task {
            try? await Task.sleep(for: .seconds(ExpeditionDeparture.duration))
            departedAt = nil
        }
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

    private func selectHair(_ id: String) {
        let state = ensureStyle()
        state.hairStyleId = id
        state.updatedAt = .now
        try? context.save()
    }

    private func selectAccessory(_ id: String) {
        let state = ensureStyle()
        state.accessoryId = id
        state.updatedAt = .now
        try? context.save()
    }

    /// 連れるペットを選ぶ（"none" で連れていない状態に戻す）。
    private func selectPet(_ id: String) {
        let state = ensurePetState()
        state.petId = id
        state.updatedAt = .now
        try? context.save()
    }

    /// ペットの保存先を必要になった時に作る。
    private func ensurePetState() -> PetState {
        if let existing = pets.first { return existing }
        let created = PetState(userId: userId)
        context.insert(created)
        return created
    }

    // MARK: - 課金（見た目のみ・非消耗型）

    /// 1.4.1 より前のダミー購入の名残。当時「購入」を押すとタダで所持扱いになっていた。
    /// 書き込み口はもう無いので増えないが、当時のテスターから取り上げはしない。
    /// 所持している見た目のコンテンツ id（スキン / 髪型 / アクセサリー）。
    /// 無料のものは含まれないが、`isOwned(_:purchased:)` が無料を常に所持とみなすので問題ない。
    private var ownedCosmeticIds: Set<String> {
        var owned = legacyGrants
        for entry in StoreCatalog.all where entry.kind != .pet {
            if store.isOwned(entry.productID) { owned.insert(entry.contentID) }
        }
        return owned
    }

    private var legacyGrants: Set<String> {
        (loadout?.purchasedSkins ?? []).union(style?.purchased ?? [])
    }

    /// 所持しているか。StoreKit の所持と、レガシー付与の和集合で見る。
    private func isOwned(_ kind: StoreCatalog.Kind, _ contentID: String) -> Bool {
        if legacyGrants.contains(contentID) { return true }
        guard let entry = StoreCatalog.entry(kind: kind, contentID: contentID) else { return false }
        return store.isOwned(entry.productID)
    }

    /// 表示価格。StoreKit から取れなければ控えの価格、日本以外では出さない
    /// （円建ての控え価格を海外に見せると誤った価格提示になる）。
    private func priceText(_ kind: StoreCatalog.Kind, _ contentID: String) -> String {
        guard let entry = StoreCatalog.entry(kind: kind, contentID: contentID) else { return "—" }
        if let price = store.displayPrice(for: entry.productID) { return price }
        guard StoreCatalog.priceFallbackAllowed(regionCode: Locale.current.region?.identifier) else { return "—" }
        return "\(entry.fallbackPrice)（参考）"
    }

    /// 見た目の購入。成功したら true（呼び出し側がそのまま着せる）。
    private func purchase(_ kind: StoreCatalog.Kind, _ contentID: String) async -> Bool {
        guard let entry = StoreCatalog.entry(kind: kind, contentID: contentID) else { return false }
        switch await store.purchase(productID: entry.productID) {
        case .purchased:
            return true
        case .cancelled:
            return false
        case .pending:
            errors.report("購入の承認を待っています。承認されると反映されます。")
            return false
        case .unavailable:
            errors.report("いまは購入できません。通信状況を確かめて、しばらくしてからお試しください。")
            return false
        case .failed(let reason):
            errors.report("購入できませんでした。\(reason)")
            return false
        }
    }

    /// 購入の復元。結果の一言を返し、シートに出す（押しても何も出ないと成否が分からない）。
    private func restorePurchases() async -> String? {
        let outcome = await store.restore()
        if case .failed = outcome {
            errors.report(outcome.message)
            return nil
        }
        return outcome.message
    }

    private var style: CharacterStyle? { styles.first }

    /// 髪型・アクセサリーの保存先を必要になった時に作る。
    private func ensureStyle() -> CharacterStyle {
        if let existing = style { return existing }
        let created = CharacterStyle(userId: userId)
        context.insert(created)
        return created
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
