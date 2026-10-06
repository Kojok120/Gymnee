import SwiftUI

/// 戦闘画面に立つ者（仲間・コーチ・ペット）の識別子。
enum BattleActorID: Hashable, Sendable {
    case member(UUID)
    case coach
    case pet
}

/// 戦闘画面の配置（issue #137）。奥にボス、手前に仲間が背中を向けて1列に並ぶ（背面視点）。
/// 描画とタップの当たり判定の両方がこれを使う。
struct BattleLayout {
    let size: CGSize
    /// 背景（石壁・石畳）の 1 ドット。
    let dot: CGFloat
    /// 壁と床の境目（pt）。
    let horizon: CGFloat
    /// ボスの 1 ドット（ランクで大きさが変わる）。
    let bossDot: CGFloat
    /// ボスの足元（中心）。
    let bossFeet: CGPoint
    /// ボスの頭のてっぺん（王冠込み）。HP ゲージはこの上に置く。
    let bossTop: CGFloat
    /// 仲間の 1 ドット。人数が多いと詰める。
    let actorDot: CGFloat
    /// 仲間の足元。左から順。
    let slots: [BattleActorID: CGPoint]

    /// 横に並べる位置（0...1）。真ん中に自分が来るよう、呼び出し側が並びを決める。
    static func columns(count: Int) -> [CGFloat] {
        switch count {
        case ...1: return [0.5]
        case 2: return [0.36, 0.64]
        case 3: return [0.22, 0.5, 0.78]
        case 4: return [0.14, 0.38, 0.62, 0.86]
        default: return [0.1, 0.3, 0.5, 0.7, 0.9]
        }
    }

    init(size: CGSize, bottomReserve: CGFloat, actors: [BattleActorID], bossSprite: PixelSprite, tier: PartyBoss.Tier) {
        self.size = size
        let dot = max(3, (size.width / 96).rounded(.down))
        self.dot = dot
        let horizon = ((size.height * 0.46) / dot).rounded() * dot
        self.horizon = horizon
        let base = (min(size.width * 0.40, horizon * 0.55) / 16).rounded(.down)
        let scale: CGFloat = tier == .weak ? 0.75 : (tier == .strong ? 1.2 : 1)
        let bossDot = max(3, (base * scale).rounded(.down))
        self.bossDot = bossDot
        let feet = CGPoint(x: (size.width / 2).rounded(), y: horizon + dot * 4)
        bossFeet = feet
        bossTop = feet.y - CGFloat(bossSprite.height) * bossDot
        let crowded = actors.count >= 4
        actorDot = crowded ? max(3, dot - 1) : dot
        let rowY = (size.height - bottomReserve - 18).rounded()
        let xs = Self.columns(count: actors.count)
        var slots: [BattleActorID: CGPoint] = [:]
        for (index, actor) in actors.enumerated() where index < xs.count {
            slots[actor] = CGPoint(x: (size.width * xs[index]).rounded(), y: rowY)
        }
        self.slots = slots
    }

    /// 仲間の当たり判定（体と頭上の名札）。
    func hitRect(for actor: BattleActorID) -> CGRect? {
        guard let feet = slots[actor] else { return nil }
        let width = CGFloat(PixelCharacterArt.canvasWidth) * actorDot
        let height = CGFloat(PixelCharacterArt.canvasHeight) * actorDot + 34
        return CGRect(x: feet.x - width / 2, y: feet.y - height, width: width, height: height)
    }

    /// 宝箱の当たり判定（ボスが立っていた場所）。
    var chestRect: CGRect {
        let side = 12 * (actorDot + 1)
        return CGRect(x: bossFeet.x - side, y: bossFeet.y - side * 1.4, width: side * 2, height: side * 1.8)
    }
}

/// 戦闘画面の動く層（issue #137）。松明の炎・ボス・仲間・攻撃の演出を毎フレーム描く。
/// 状態は持たず、渡された時刻つきの演出（`BossBattleStage.Strike`）から絵を決める。
struct BossBattleStage: View {
    struct Actor: Identifiable {
        let id: BattleActorID
        /// 人として描くときの姿（ペットは nil）。
        let look: PixelCharacterRenderer.Look?
        let pet: PetCatalog.Pet?
        let name: String
        let job: PartyBoss.Job?
        /// トレ中（戦闘中の動きで、ときどきボスを殴る）。
        let isLive: Bool
    }

    /// 再生中の1回の攻撃の演出。
    struct Strike: Equatable {
        let actor: BattleActorID
        let startedAt: Date
        /// 基本のダメージ（0 なら数字を出さない）。
        let damage: Int
        /// 上乗せ（「連携 +1」「底力 +1」）。
        let bonuses: [String]
    }

    let layout: BattleLayout
    let bossId: String
    let tier: PartyBoss.Tier
    let actors: [Actor]
    let strike: Strike?
    /// ボスの見え方（1 = 立っている / 0 = 倒れて消えた）。倒れる途中は時刻から計算する。
    let defeatStartedAt: Date?
    let bossGone: Bool
    let angry: Bool
    /// 宝箱（nil なら出さない。true なら開いている）。
    let chestOpened: Bool?
    let sceneStart: Date

    /// 攻撃の段取り（秒）。踏みこみ → 命中 → 数字が昇る。
    static let impactAt: TimeInterval = 0.45
    static let collapseDuration: TimeInterval = 1.0

    private static let accent = Color(hexF: 0xC6FF3D)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let now = timeline.date
                drawTorches(&context, now: now)
                drawBoss(&context, now: now)
                drawActors(&context, now: now)
                drawStrikeEffects(&context, now: now)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - 松明

    private func drawTorches(_ context: inout GraphicsContext, now: Date) {
        let t = now.timeIntervalSince(sceneStart)
        let dot = layout.dot
        let cols = (layout.size.width / dot).rounded(.up)
        let horizonRow = (layout.horizon / dot).rounded()
        for (index, ratio) in DungeonBackdrop.torchXs.enumerated() {
            // 2本が同じ揺れ方にならないよう、コマの進みをずらす。
            let tick = Int(t / 0.14) &+ index * 5
            let frame = PixelDungeonArt.flameFrames[(tick &* 7 &+ tick / 3) % PixelDungeonArt.flameFrames.count]
            let x = (cols * ratio).rounded() - CGFloat(PixelDungeonArt.bracket.width / 2)
            let y = (horizonRow * DungeonBackdrop.torchY).rounded() - CGFloat(frame.height)
            context.drawPixels(frame, at: CGPoint(x: x * dot, y: y * dot), dot: dot, palette: PixelDungeonArt.palette)
        }
    }

    // MARK: - ボス

    private func strikeElapsed(_ now: Date) -> TimeInterval? {
        strike.map { now.timeIntervalSince($0.startedAt) }
    }

    /// 命中の瞬間に白く点滅する区間。
    private func isFlashing(_ elapsed: TimeInterval) -> Bool {
        let t = elapsed - Self.impactAt
        return (t >= 0 && t < 0.08) || (t >= 0.16 && t < 0.24)
    }

    private func bossOpacity(_ now: Date) -> Double {
        if let start = defeatStartedAt {
            return max(0, 1 - now.timeIntervalSince(start) / Self.collapseDuration)
        }
        return bossGone ? 0 : 1
    }

    private func drawBoss(_ context: inout GraphicsContext, now: Date) {
        let t = now.timeIntervalSince(sceneStart)
        let dot = layout.bossDot
        let sprite = PixelBossArt.sprite(bossId: bossId, tier: tier)
        let width = CGFloat(sprite.width) * dot
        let height = CGFloat(sprite.height) * dot
        let opacity = bossOpacity(now)

        // 足元の影。段を重ねた楕円。
        let shadowW = width * 0.8
        for (index, scale) in [1.0, 0.75].enumerated() {
            let w = (shadowW * scale / layout.dot).rounded() * layout.dot
            let h = layout.dot * CGFloat(2 - index)
            context.fill(
                Path(CGRect(x: (layout.bossFeet.x - w / 2).rounded(), y: layout.bossFeet.y - h / 2, width: w, height: h)),
                with: .color(.black.opacity(0.30 * max(opacity, 0.4)))
            )
        }

        if let opened = chestOpened, opacity < 0.5 {
            drawChest(&context, now: now, opened: opened)
        }
        guard opacity > 0 else { return }

        // 強いボスの赤い気配。段で重ねる（ぼかしは使わない）。
        if tier == .strong {
            for (grow, alpha) in [(4.0, 0.10), (2.0, 0.14)] {
                let g = CGFloat(grow) * dot
                context.fill(
                    Path(CGRect(x: layout.bossFeet.x - width / 2 - g, y: layout.bossFeet.y - height - g / 2,
                                width: width + g * 2, height: height + g / 2)),
                    with: .color(Color(hexF: 0xFF3B30).opacity(alpha * opacity))
                )
            }
        }

        // 待機の上下（2コマ）。倒れる間は沈む。
        let bob: CGFloat = Int(t / 0.6) % 2 == 0 ? 0 : 1
        var sink: CGFloat = 0
        if let start = defeatStartedAt {
            sink = (CGFloat(min(1, now.timeIntervalSince(start) / Self.collapseDuration)) * 4).rounded()
        }
        var shakeX: CGFloat = 0
        var palette = PixelBossArt.palette(bossId: bossId, tier: tier)
        if let elapsed = strikeElapsed(now), elapsed >= Self.impactAt, elapsed < Self.impactAt + 0.35 {
            shakeX = Int(elapsed / 0.05) % 2 == 0 ? dot : -dot
            if isFlashing(elapsed) { palette = PixelDungeonArt.flashPalette }
        }
        if let start = defeatStartedAt, Int(now.timeIntervalSince(start) / 0.1) % 2 == 0 {
            palette = PixelDungeonArt.flashPalette
        }
        let origin = CGPoint(
            x: (layout.bossFeet.x - width / 2 + shakeX).rounded(),
            y: (layout.bossFeet.y - height - (bob - sink) * dot).rounded()
        )
        context.drawPixels(sprite, at: origin, dot: dot, palette: palette, opacity: opacity)

        // 怒りマーク（HP が半分を切ったら、点滅させる）。
        if angry, defeatStartedAt == nil, Int(t / 0.5) % 2 == 0 {
            let markDot = max(2, (dot * 0.6).rounded())
            context.drawPixels(
                PixelDungeonArt.anger,
                at: CGPoint(x: (origin.x + width - markDot * 5).rounded(), y: (origin.y + dot).rounded()),
                dot: markDot, palette: PixelDungeonArt.angerPalette
            )
        }
    }

    private func drawChest(_ context: inout GraphicsContext, now: Date, opened: Bool) {
        let dot = layout.actorDot + 1
        let tick = Int(now.timeIntervalSince(sceneStart) / 0.4)
        let bounce = !opened && tick % 2 == 0
        let sprite = PixelCharacterArt.chest(opened ? 2 : (bounce ? 1 : 0))
        let origin = CGPoint(
            x: (layout.bossFeet.x - CGFloat(sprite.width) * dot / 2).rounded(),
            y: (layout.bossFeet.y - CGFloat(sprite.height) * dot - (bounce ? dot : 0)).rounded()
        )
        context.drawPixels(sprite, at: origin, dot: dot, palette: .neutral)
        if bounce {
            var palette = PixelPalette.item(rarity: .epic)
            palette.accent = Self.accent
            context.drawPixels(PixelCharacterArt.sparkle,
                               at: CGPoint(x: origin.x + CGFloat(sprite.width) * dot - dot, y: origin.y - dot * 5),
                               dot: dot, palette: palette)
        }
    }

    // MARK: - 仲間

    /// 踏みこみの量（ドット、上＝負）。命中の少し前に一番前へ出て、戻る。
    private static func lunge(_ elapsed: TimeInterval) -> Int {
        switch elapsed {
        case ..<0: return 0
        case ..<0.15: return -1
        case ..<0.45: return -3
        case ..<0.65: return -2
        case ..<0.8: return -1
        default: return 0
        }
    }

    /// トレ中の仲間は、ときどき勝手に殴りに行く（周期は人ごとにずらす）。
    private func liveElapsed(for actor: Actor, now: Date) -> TimeInterval? {
        guard actor.isLive else { return nil }
        let period = 3.4
        let offset = Double(abs(actor.id.hashValue) % 1000) / 1000 * period
        return (now.timeIntervalSince(sceneStart) + offset).truncatingRemainder(dividingBy: period)
    }

    private func drawActors(_ context: inout GraphicsContext, now: Date) {
        let dot = layout.actorDot
        for actor in actors {
            guard let feet = layout.slots[actor.id] else { continue }
            var elapsed: TimeInterval?
            if let strike, strike.actor == actor.id { elapsed = now.timeIntervalSince(strike.startedAt) }
            if elapsed == nil { elapsed = liveElapsed(for: actor, now: now) }
            let step = elapsed.map(Self.lunge) ?? 0
            let point = CGPoint(x: feet.x, y: feet.y + CGFloat(step) * dot)

            if let look = actor.look {
                var frame = PixelCharacterLayout.Frame.standing
                if let elapsed, elapsed < 0.8 {
                    // 振りかぶって殴る（腕を挙げる）。
                    frame.armsRaised = elapsed >= 0.1 && elapsed < 0.55
                    frame.lift = elapsed >= 0.1 && elapsed < 0.45 ? -1 : 0
                }
                PixelCharacterRenderer.draw(in: &context, look: look, frame: frame, facing: .up, feet: point, dot: dot)
            } else if let pet = actor.pet {
                let sprite = PixelPetArt.sprite(petId: pet.id, facing: .up, blink: false)
                let hop: CGFloat = Int(now.timeIntervalSince(sceneStart) / 0.5) % 4 == 0 ? dot : 0
                context.drawPixels(
                    sprite,
                    at: CGPoint(x: (point.x - CGFloat(sprite.width) * dot / 2).rounded(),
                                y: (point.y - CGFloat(sprite.height) * dot - hop).rounded()),
                    dot: dot, palette: PixelPetArt.palette(petId: pet.id)
                )
            }
            drawLabel(&context, actor: actor, feet: point, now: now)
        }
    }

    /// 頭上の名札（ジョブと名前）。トレ中なら上に印を出す。
    private func drawLabel(_ context: inout GraphicsContext, actor: Actor, feet: CGPoint, now: Date) {
        let dot = layout.actorDot
        let height: CGFloat = actor.look != nil
            ? CGFloat(PixelCharacterArt.canvasHeight) * dot
            : CGFloat(PixelPetArt.canvasHeight) * dot
        var y = feet.y - height - 4
        let name = context.resolve(
            Text(actor.name).font(.pixel(size: 11, relativeTo: .caption2)).foregroundStyle(Color.white)
        )
        y = drawPlate(&context, text: name, centerX: feet.x, bottom: y, fill: .black.opacity(0.6))
        if let job = actor.job {
            let jobText = context.resolve(
                Text("\(Image(systemName: job.symbol)) \(job.label)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
            )
            y = drawPlate(&context, text: jobText, centerX: feet.x, bottom: y - 2, fill: .black.opacity(0.4))
        }
        if actor.isLive, Int(now.timeIntervalSince(sceneStart) / 0.6) % 2 == 0 {
            let live = context.resolve(
                Text("戦闘中").font(.pixel(size: 10, relativeTo: .caption2)).foregroundStyle(Color.black)
            )
            _ = drawPlate(&context, text: live, centerX: feet.x, bottom: y - 2, fill: Self.accent)
        }
    }

    /// 文字の台座を描き、台座の上端を返す。
    private func drawPlate(_ context: inout GraphicsContext, text: GraphicsContext.ResolvedText,
                           centerX: CGFloat, bottom: CGFloat, fill: Color) -> CGFloat {
        let size = text.measure(in: CGSize(width: 160, height: 40))
        let box = CGRect(x: (centerX - size.width / 2 - 4).rounded(), y: (bottom - size.height - 2).rounded(),
                         width: (size.width + 8).rounded(), height: (size.height + 2).rounded())
        context.fill(Path(box), with: .color(fill))
        context.draw(text, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
        return box.minY
    }

    // MARK: - 攻撃の演出

    private func drawStrikeEffects(_ context: inout GraphicsContext, now: Date) {
        let center = CGPoint(x: layout.bossFeet.x, y: (layout.bossFeet.y + layout.bossTop) / 2)
        // トレ中の仲間の空振り（数字は出さない、きらめきだけ）。
        for actor in actors {
            guard strike?.actor != actor.id, let elapsed = liveElapsed(for: actor, now: now),
                  elapsed >= Self.impactAt, elapsed < Self.impactAt + 0.25, !bossGone
            else { continue }
            var palette = PixelPalette.item(rarity: .epic)
            palette.accent = Self.accent
            let dot = layout.actorDot
            let side = CGFloat(PixelCharacterArt.sparkle.width) * dot
            let jitter = CGFloat(abs(actor.id.hashValue) % 5 - 2) * dot * 3
            context.drawPixels(PixelCharacterArt.sparkle,
                               at: CGPoint(x: (center.x - side / 2 + jitter).rounded(), y: (center.y - side / 2).rounded()),
                               dot: dot, palette: palette)
        }

        guard let strike else { return }
        let elapsed = now.timeIntervalSince(strike.startedAt)
        let t = elapsed - Self.impactAt
        guard t >= 0 else { return }

        // 斬撃（命中から 0.25 秒）。
        if t < 0.25 {
            let dot = max(3, layout.bossDot * 0.8).rounded()
            let side = CGFloat(PixelDungeonArt.slash.width) * dot
            context.drawPixels(PixelDungeonArt.slash,
                               at: CGPoint(x: (center.x - side / 2).rounded(), y: (center.y - side / 2).rounded()),
                               dot: dot, palette: PixelDungeonArt.slashPalette, opacity: 1 - t / 0.25)
        }

        // ダメージの数字（命中から 0.9 秒かけて昇って消える）。
        if strike.damage > 0, t < 0.9 {
            drawPopup(&context, text: "\(strike.damage)", size: 30, color: .white,
                      at: CGPoint(x: center.x + layout.bossDot * 3, y: center.y - CGFloat(t) * 60), opacity: 1 - max(0, t - 0.6) / 0.3)
        }
        // 上乗せ（連携・スキル）は少し遅れて順に出す。
        for (index, bonus) in strike.bonuses.enumerated() {
            let bt = t - 0.45 - Double(index) * 0.35
            guard bt >= 0, bt < 1.0 else { continue }
            drawPopup(&context, text: bonus, size: 16, color: Self.accent,
                      at: CGPoint(x: center.x - layout.bossDot * 3, y: center.y - 10 - CGFloat(bt) * 40),
                      opacity: 1 - max(0, bt - 0.7) / 0.3)
        }
    }

    /// 縁取りした文字を浮かせる。
    private func drawPopup(_ context: inout GraphicsContext, text: String, size: CGFloat, color: Color,
                           at point: CGPoint, opacity: Double) {
        let outline = context.resolve(Text(text).font(.pixel(size: size)).foregroundStyle(Color.black.opacity(0.85 * opacity)))
        for offset in [CGSize(width: -2, height: 0), CGSize(width: 2, height: 0), CGSize(width: 0, height: -2), CGSize(width: 0, height: 2)] {
            context.draw(outline, at: CGPoint(x: point.x + offset.width, y: point.y + offset.height), anchor: .center)
        }
        let fill = context.resolve(Text(text).font(.pixel(size: size)).foregroundStyle(color.opacity(opacity)))
        context.draw(fill, at: point, anchor: .center)
    }
}
