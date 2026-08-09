import SwiftUI

/// キャラ本体の描画。トレーニーの体をベクターで描き、装備を重ねる。
///
/// 体格は `CharacterAppearance`（＝現実の記録の写し）で決まる。押す力で肩、腕力で腕、脚力で脚が太くなり、
/// 進化段階でオーラが強くなる。装備は姿に重なるが体格には影響しない（強さは現実だけ、が崩れないように）。
struct CharacterFigureView: View {
    let appearance: CharacterAppearance
    let stage: CharacterProgress.Stage
    let skin: CharacterSkin
    /// 部位ごとの装備。
    let equipped: [Expedition.Slot: Expedition.Item]
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            if appearance.aura > 0 || equipped[.aura] != nil {
                auraLayer
            }
            Canvas { context, canvasSize in
                draw(in: &context, size: canvasSize)
            }
            .frame(width: size, height: size)
            equipmentLayer
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(stage.title)のキャラクター")
    }

    // MARK: - 体

    private var bodyColor: Color { Color(hexF: skin.bodyHex) }
    private var accentColor: Color { Color(hexF: skin.accentHex) }

    /// 正面向きのトレーニー。頭・首・胴・腕・脚を角丸で組み、太さをステータスで変える。
    private func draw(in context: inout GraphicsContext, size canvas: CGSize) {
        let w = canvas.width
        let h = canvas.height
        let cx = w / 2

        let headR = h * 0.085
        let headY = h * 0.16
        let shoulderY = headY + headR * 1.7
        let hipY = h * 0.60
        let footY = h * 0.94

        let shoulderHalf = w * (0.13 + 0.10 * appearance.shoulder)
        let waistHalf = w * (0.075 + 0.045 * appearance.torso)
        let armW = w * (0.045 + 0.040 * appearance.arm)
        let legW = w * (0.060 + 0.045 * appearance.leg)

        let body = GraphicsContext.Shading.color(bodyColor)
        let wear = GraphicsContext.Shading.color(accentColor)

        // 脚（先に描いて胴の下に潜らせる）
        for side in [-1.0, 1.0] {
            let x = cx + side * (waistHalf * 0.52)
            let rect = CGRect(x: x - legW / 2, y: hipY - h * 0.06, width: legW, height: footY - hipY + h * 0.06)
            context.fill(Path(roundedRect: rect, cornerRadius: legW / 2), with: body)
        }
        // ショートパンツ（腰から左右の脚をまたいで 1 枚で描く）
        let shortsWidth = waistHalf * 2 + legW * 0.5
        let shorts = CGRect(x: cx - shortsWidth / 2, y: hipY - h * 0.02, width: shortsWidth, height: h * 0.13)
        context.fill(Path(roundedRect: shorts, cornerRadius: legW / 2.6), with: wear)

        // 腕（肩の丸み → 上腕 の順で、肩から生えて見えるように繋ぐ）
        for side in [-1.0, 1.0] {
            let x = cx + side * (shoulderHalf - armW * 0.15)
            let rect = CGRect(x: x - armW / 2, y: shoulderY - h * 0.005, width: armW, height: hipY - shoulderY + h * 0.07)
            context.fill(Path(roundedRect: rect, cornerRadius: armW / 2), with: body)
            // 三角筋。肩幅が広いほど大きくなり、胴との隙間を埋める。
            let deltoid = armW * 1.12
            context.fill(
                Path(ellipseIn: CGRect(x: x - deltoid / 2, y: shoulderY - deltoid * 0.42, width: deltoid, height: deltoid)),
                with: body
            )
        }

        // 胴（台形を角丸パスで近似）
        var torso = Path()
        torso.move(to: CGPoint(x: cx - shoulderHalf, y: shoulderY))
        torso.addLine(to: CGPoint(x: cx + shoulderHalf, y: shoulderY))
        torso.addLine(to: CGPoint(x: cx + waistHalf, y: hipY))
        torso.addLine(to: CGPoint(x: cx - waistHalf, y: hipY))
        torso.closeSubpath()
        context.fill(torso, with: body)

        // タンクトップ（襟を肩より少し下げ、首が見えるようにする）
        var tank = Path()
        tank.move(to: CGPoint(x: cx - shoulderHalf * 0.58, y: shoulderY + h * 0.022))
        tank.addLine(to: CGPoint(x: cx + shoulderHalf * 0.58, y: shoulderY + h * 0.022))
        tank.addLine(to: CGPoint(x: cx + waistHalf, y: hipY))
        tank.addLine(to: CGPoint(x: cx - waistHalf, y: hipY))
        tank.closeSubpath()
        context.fill(tank, with: wear)

        // 首（タンクトップの襟より上に出す）・頭
        let neck = CGRect(x: cx - w * 0.032, y: headY + headR * 0.5, width: w * 0.064, height: shoulderY - headY - headR * 0.3)
        context.fill(Path(roundedRect: neck, cornerRadius: w * 0.024), with: body)
        context.fill(Path(ellipseIn: CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)), with: body)
    }

    // MARK: - オーラ

    private var auraLayer: some View {
        let strength = max(appearance.aura, equipped[.aura] != nil ? 0.7 : 0)
        return Circle()
            .fill(
                RadialGradient(
                    colors: [auraColor.opacity(0.35 * strength), .clear],
                    center: .center, startRadius: size * 0.18, endRadius: size * 0.52
                )
            )
            .frame(width: size, height: size)
    }

    private var auraColor: Color {
        switch equipped[.aura]?.rarity {
        case .epic: return Theme.warning
        case .rare: return Theme.info
        case .common: return Theme.lime
        case nil: return Theme.lime
        }
    }

    // MARK: - 装備（体の上に重ねる）

    @ViewBuilder
    private var equipmentLayer: some View {
        ZStack {
            if let head = equipped[.head] {
                // 頭頂（Canvas の頭の中心は上から 0.16、半径 0.085）。
                badge(head)
                    .offset(y: -size * 0.415)
            }
            if let hand = equipped[.hand] {
                // 両手（腕の下端あたり）。
                badge(hand).offset(x: -size * 0.20, y: size * 0.16)
                badge(hand).offset(x: size * 0.20, y: size * 0.16)
            }
            if let waist = equipped[.waist] {
                Capsule()
                    .fill(rarityColor(waist.rarity))
                    .frame(width: size * 0.26, height: size * 0.035)
                    .offset(y: size * 0.10)
                    .overlay {
                        Image(systemName: waist.symbol)
                            .font(.system(size: size * 0.045, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(y: size * 0.10)
                    }
            }
        }
        .frame(width: size, height: size)
    }

    private func badge(_ item: Expedition.Item) -> some View {
        Image(systemName: item.symbol)
            .font(.system(size: size * 0.075, weight: .semibold))
            .foregroundStyle(rarityColor(item.rarity))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }

    private func rarityColor(_ rarity: Expedition.Rarity) -> Color {
        switch rarity {
        case .common: return Theme.textSecondary
        case .rare: return Theme.info
        case .epic: return Theme.warning
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        CharacterFigureView(
            appearance: CharacterAppearance(shoulder: 0.35, arm: 0.3, leg: 0.3, torso: 0.35, aura: 0),
            stage: .rookie, skin: SkinCatalog.all[0], equipped: [:], size: 150
        )
        CharacterFigureView(
            appearance: CharacterAppearance(shoulder: 1, arm: 1, leg: 1, torso: 1, aura: 1),
            stage: .legend, skin: SkinCatalog.all[3],
            equipped: [.head: Expedition.items.first { $0.id == "crown" }!,
                       .waist: Expedition.items.first { $0.id == "champion-belt" }!],
            size: 150
        )
    }
    .padding()
    .background(Theme.bg0)
}
