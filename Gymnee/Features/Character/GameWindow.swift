import SwiftUI

// ボス部屋とパーティのメニューで使う、ゲームの窓とコマンド（issue #161）。
//
// iOS の確認窓・シート・Menu はドット絵の画面から浮くので、ボス部屋の中で問いかける・選ばせるときは
// メッセージ窓と同じ「黒地に白い枠」の窓と、▶ のカーソルが付くコマンドを使う。

enum GameWindowStyle {
    static let fill = Color.black.opacity(0.88)
    static let border = Color.white
    static let lineWidth: CGFloat = 2.5
    static let radius: CGFloat = 6
    static let accent = Color(hexF: 0xC6FF3D)
    /// 選べないコマンド・補足の文字。
    static let muted = Color.white.opacity(0.55)
}

extension View {
    /// メッセージ窓と同じ黒地・白枠の窓。
    func gameWindow(padding: CGFloat = Theme.Spacing.md, border: Color = GameWindowStyle.border) -> some View {
        self
            .padding(padding)
            .background(GameWindowStyle.fill, in: RoundedRectangle(cornerRadius: GameWindowStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: GameWindowStyle.radius)
                .strokeBorder(border, lineWidth: GameWindowStyle.lineWidth))
    }
}

/// ▶ のカーソル。ドットで描く（フォントの記号だと字形が揃わない）。点滅は「動きを減らす」で止める。
struct GameCursor: View {
    var visible = true
    var dot: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 右向きの三角（幅 4・高さ 7 ドット）。
    private static let rows = [1, 2, 3, 4, 3, 2, 1]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let blinkOn = reduceMotion || Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Canvas { context, size in
                let top = (size.height - CGFloat(Self.rows.count) * dot) / 2
                for (row, width) in Self.rows.enumerated() {
                    context.fill(Path(CGRect(x: 0, y: top + CGFloat(row) * dot, width: CGFloat(width) * dot, height: dot)),
                                 with: .color(.white))
                }
            }
            .opacity(visible && blinkOn ? 1 : 0)
        }
        .frame(width: 4 * dot + 6, height: 7 * dot)
        .accessibilityHidden(true)
    }
}

/// カーソル付きのコマンド。押すと選ぶ音を鳴らす。
struct GameCommand: View {
    let title: String
    var selected = false
    var enabled = true
    var size: CGFloat = 17
    let action: () -> Void

    var body: some View {
        Button {
            GameSound.play(.select)
            action()
        } label: {
            HStack(spacing: 2) {
                GameCursor(visible: selected)
                Text(title)
                    .font(.pixel(size: size, relativeTo: .body))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(enabled ? Color.white : GameWindowStyle.muted)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 「はい / いいえ」。メッセージ窓で問いかけたときに、下の帯の代わりに出す。
struct GameChoiceBar: View {
    var yes = "はい"
    var no = "いいえ"
    /// 処理中（押せない）。
    var busy = false
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            GameCommand(title: yes, selected: true, enabled: !busy, size: 19, action: onYes)
            GameCommand(title: no, enabled: !busy, size: 19, action: onNo)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .gameWindow(padding: 2)
    }
}

/// 今週の回数のマス（目標の数＋上乗せ 1 つ。上乗せのマスは空なら枠だけ）。
struct HitPipsView: View {
    let pips: PartyBoss.Pips
    var side: CGFloat = 9

    var body: some View {
        HStack(spacing: max(2, side / 3)) {
            ForEach(0..<pips.slots, id: \.self) { index in
                Rectangle()
                    .fill(fill(index))
                    .overlay {
                        if pips.isBonus(index), !pips.isFilled(index) {
                            Rectangle().strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        }
                    }
                    .frame(width: side, height: side)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("今週 \(pips.filled)回、目標 \(pips.goal)回")
    }

    private func fill(_ index: Int) -> Color {
        if pips.isFilled(index) { return GameWindowStyle.accent }
        return pips.isBonus(index) ? .clear : Color.white.opacity(0.2)
    }
}
