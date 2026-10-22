import SwiftUI

/// 記録画面の戦闘の帯（issue #155）。レスト欄の上に重ね、セットを記録するたびに主人公が技を出す。
///
/// 帯は**見せるだけ**で、記録の操作（種目カード）を邪魔しない。押しても何も起きず、
/// 高さも 1 行に収める。数え方は `RecordBattle`（純粋関数）が決め、ここは描くだけ。
struct RecordBattleStrip: View {
    let opponent: RecordBattle.Opponent
    let look: PixelCharacterRenderer.Look
    /// 今日の 1 撃ぶんをどこまで削ったか（0...1）。
    let chip: Double
    /// 最後の一撃。id が変わるたびに演出を 1 回流す。
    let strike: Strike?
    /// チュートリアルのちびスライムを倒した（宝箱を出す）。
    let tutorialCleared: Bool
    /// とどめの演出中。
    let finishing: Bool

    struct Strike: Equatable, Identifiable {
        let id = UUID()
        /// 浮かべる数字（挙げた量・回数・秒）。
        let label: String
        /// メッセージに出す言葉。
        let line: String
        let isCritical: Bool
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lunge = false
    @State private var hitFlash = false
    @State private var shake = false
    @State private var popup: Strike?
    @State private var popupRise = false
    @State private var message: String?

    static let height: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {
            hero
                .offset(x: lunge ? 18 : 0)
            center
                .frame(maxWidth: .infinity)
            enemy
                .offset(x: shake ? 3 : 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Self.height)
        .background(backdrop)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .padding(.horizontal, Theme.Spacing.lg)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onChange(of: strike?.id) { _, _ in play(strike) }
        .onChange(of: finishing) { _, now in if now { playFinish() } }
    }

    // MARK: - 部品

    private var hero: some View {
        Canvas { context, size in
            let dot: CGFloat = 2
            PixelCharacterRenderer.draw(
                in: &context, look: look, frame: .standing, facing: .right,
                feet: CGPoint(x: size.width / 2, y: size.height - 2), dot: dot
            )
        }
        .frame(width: 52, height: Self.height - 6)
    }

    private var enemy: some View {
        VStack(spacing: 3) {
            hpBar
                .frame(height: 5)
            ZStack {
                enemySprite
                    .opacity(defeated ? 0 : 1)
                    .brightness(hitFlash ? 0.6 : 0)
                if defeated && opponent == .tutorial {
                    PixelSpriteView(sprite: PixelCharacterArt.chest(2), palette: .neutral, side: 36)
                        .transition(.scale.combined(with: .opacity))
                }
                if hitFlash {
                    PixelSpriteView(sprite: PixelDungeonArt.slash, palette: PixelDungeonArt.slashPalette, side: 40)
                }
            }
            .frame(height: 48)
        }
        .frame(width: 64, height: Self.height - 6)
    }

    @ViewBuilder
    private var enemySprite: some View {
        switch opponent {
        case .tutorial:
            // ちびスライムは小さく（弱いランクの絵をさらに縮める）。
            PixelSpriteView(sprite: PixelBossArt.slime, palette: PixelBossArt.palette(bossId: "sloth_slime", tier: .weak), side: 32)
        case .boss(let bossId, let tier, _, _):
            PixelSpriteView(sprite: PixelBossArt.sprite(bossId: bossId, tier: tier),
                            palette: PixelBossArt.palette(bossId: bossId, tier: tier), side: 48)
        case .dummy:
            PixelSpriteView(sprite: PixelBossArt.trainingDummy, palette: PixelBossArt.trainingDummyPalette, side: 48)
        }
    }

    private var defeated: Bool {
        opponent == .tutorial && tutorialCleared
    }

    /// 週ボスの HP。今日の 1 撃ぶん（右端の 1 目盛り）を、セットを重ねるたびに削って見せる。
    @ViewBuilder
    private var hpBar: some View {
        if case .boss(_, _, let remaining, let total) = opponent, total > 0 {
            GeometryReader { proxy in
                let width = proxy.size.width
                let unit = width / CGFloat(total)
                let alive = CGFloat(max(0, remaining))
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.55))
                    // 削っている途中の 1 目盛り（薄い色）の上に、まだ削っていない分を濃い色で重ねる。
                    Rectangle().fill(Color(hexF: 0xFF8A3D).opacity(0.35))
                        .frame(width: max(0, unit * alive))
                    Rectangle().fill(Color(hexF: 0xFF8A3D))
                        .frame(width: max(0, unit * (alive - CGFloat(chip))))
                }
                .clipShape(Capsule())
            }
            .frame(width: 52, height: 5)
        } else if opponent == .tutorial && !tutorialCleared {
            Capsule().fill(Color(hexF: 0xFF8A3D)).frame(width: 30, height: 5)
        } else {
            Color.clear.frame(width: 52, height: 5)
        }
    }

    private var center: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(message ?? idleMessage)
                    .font(.pixel(size: 12, relativeTo: .caption))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
            }
            if let popup {
                Text(popup.isCritical ? "\(popup.label)!!" : popup.label)
                    .font(.pixel(size: popup.isCritical ? 22 : 17, relativeTo: .title3))
                    .foregroundStyle(popup.isCritical ? Color(hexF: 0xFFE066) : .white)
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .offset(x: 34, y: popupRise ? -22 : -6)
                    .opacity(popupRise ? 0 : 1)
            }
        }
    }

    private var idleMessage: String {
        switch opponent {
        case .tutorial:
            return tutorialCleared ? "宝箱を手に入れた！" : "ちびスライムが あらわれた！ 1セットで たおせる"
        case .boss(let bossId, _, _, _):
            let name = PartyBoss.boss(id: bossId)?.name ?? "ボス"
            return chip >= 1 ? "\(name)が ふらついている！ 記録を終えて とどめ" : "\(name)と たたかっている"
        case .dummy(let reason):
            switch reason {
            case .noParty: return "かかしで 技の修行中"
            case .defeated: return "今週のボスは たおした！ かかしで 修行中"
            case .capped: return "今週のダメージは 上限！ かかしで 修行中"
            }
        }
    }

    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hexF: 0x2A2036), Color(hexF: 0x1A1420)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color(hexF: 0x3A2E44)).frame(height: 6)
        }
    }

    private var accessibilityText: String {
        "戦闘。\(opponent.name)。\(message ?? idleMessage)"
    }

    // MARK: - 演出

    private func play(_ strike: Strike?) {
        guard let strike else { return }
        message = strike.line
        popup = strike
        popupRise = false
        if reduceMotion {
            hitFlash = true
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) { hitFlash = false }
        } else {
            withAnimation(.easeOut(duration: 0.12)) { lunge = true }
            withAnimation(.easeIn(duration: 0.18).delay(0.12)) { lunge = false }
            withAnimation(.linear(duration: 0.05).delay(0.1)) { hitFlash = true }
            withAnimation(.linear(duration: 0.05).delay(0.3)) { hitFlash = false }
            withAnimation(.linear(duration: 0.06).repeatCount(4, autoreverses: true).delay(0.1)) { shake = true }
            withAnimation(.linear(duration: 0.01).delay(0.36)) { shake = false }
        }
        withAnimation(.easeOut(duration: 0.9).delay(0.1)) { popupRise = true }
        let id = strike.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if self.strike?.id == id { message = nil }
        }
    }

    private func playFinish() {
        message = RecordBattle.finishLine(opponent: opponent)
        popup = Strike(label: "とどめ", line: "", isCritical: true)
        popupRise = false
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.15)) { lunge = true }
            withAnimation(.easeIn(duration: 0.25).delay(0.2)) { lunge = false }
            withAnimation(.linear(duration: 0.06).repeatCount(8, autoreverses: true).delay(0.15)) { shake = true }
            withAnimation(.linear(duration: 0.01).delay(0.65)) { shake = false }
        }
        withAnimation(.linear(duration: 0.05).delay(0.15)) { hitFlash = true }
        withAnimation(.linear(duration: 0.2).delay(0.6)) { hitFlash = false }
        withAnimation(.easeOut(duration: 1.0).delay(0.2)) { popupRise = true }
    }
}

#if DEBUG
/// 帯の見え方の一覧（`-gymneeScreen battle-strip`）。演出は動かさず、相手ごとの止まった姿を並べる。
struct RecordBattleStripGallery: View {
    let look: PixelCharacterRenderer.Look

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                labelled("チュートリアル") {
                    RecordBattleStrip(opponent: .tutorial, look: look, chip: 0, strike: nil, tutorialCleared: false, finishing: false)
                }
                labelled("チュートリアル（倒した）") {
                    RecordBattleStrip(opponent: .tutorial, look: look, chip: 1, strike: nil, tutorialCleared: true, finishing: false)
                }
                labelled("週ボス（削り途中）") {
                    RecordBattleStrip(opponent: .boss(bossId: "couch_golem", tier: .medium, remainingHP: 4, totalHP: 7),
                                      look: look, chip: 0.5, strike: nil, tutorialCleared: false, finishing: false)
                }
                labelled("週ボス（強い・削りきり）") {
                    RecordBattleStrip(opponent: .boss(bossId: "junk_kraken", tier: .strong, remainingHP: 1, totalHP: 8),
                                      look: look, chip: 1, strike: nil, tutorialCleared: false, finishing: false)
                }
                labelled("かかし（パーティなし）") {
                    RecordBattleStrip(opponent: .dummy(.noParty), look: look, chip: 0.3, strike: nil, tutorialCleared: false, finishing: false)
                }
                labelled("かかし（今週は撃破済み）") {
                    RecordBattleStrip(opponent: .dummy(.defeated), look: look, chip: 0.3, strike: nil, tutorialCleared: false, finishing: false)
                }
            }
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background(Theme.bg0)
    }

    private func labelled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.Spacing.lg)
            content()
        }
    }
}
#endif
