import SwiftUI

/// コーチとの相談。
///
/// #79 の自由入力チャット（LLM・履歴保存）が入るまでの中身で、**選択肢式の会話**として成立させている。
/// 空の入力欄を置いて「準備中」と書くより、いま答えられることに絞って実際に答えるほうが役に立つ。
/// 答えは必ず現在の記録から導き、その場で押せる行動を添える（答えっぱなしにしない）。
struct CoachSheet: View {
    let topics: [CoachConsultation.Topic]
    /// コーチが開口一番に言うこと（部屋のふきだしと同じ内容）。
    let opening: String
    let onAction: (CharacterChatter.Line.Action) -> Void
    /// 用事を見送る（しばらくコーチは来なくなる）。
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// 選んだ質問（複数選べる。会話の流れとして積み上がる）。
    @State private var asked: [CoachConsultation.Topic] = []

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        coachBubble(opening)

                        ForEach(asked) { topic in
                            userBubble(topic.question)
                            coachBubble(topic.answer)
                            if let action = topic.action, let title = topic.actionTitle {
                                actionButton(title: title, action: action)
                            }
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(Theme.Spacing.lg)
                }
                .onChange(of: asked.count) { _, _ in
                    withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { questionBar }
            .background(Theme.bg0)
            .navigationTitle("コーチ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - ふきだし

    private func coachBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            CoachAvatar()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            Spacer(minLength: Theme.Spacing.xl)
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: Theme.Spacing.xl)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.onLime)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.limeFill, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        }
    }

    private func actionButton(title: String, action: CharacterChatter.Line.Action) -> some View {
        Button(title) { onAction(action) }
            .buttonStyle(.gymneePrimary)
            .padding(.leading, 44)
    }

    // MARK: - 質問の選択

    /// まだ聞いていない質問。全部聞いたら「見送る」だけが残る。
    private var remaining: [CoachConsultation.Topic] {
        topics.filter { topic in !asked.contains { $0.id == topic.id } }
    }

    private var questionBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if !remaining.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(remaining) { topic in
                            Button(topic.question) {
                                withAnimation(.snappy) { asked.append(topic) }
                            }
                            .buttonStyle(.gymneeSecondary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }
            }

            Button("またあとで") {
                onDismiss()
                dismiss()
            }
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .padding(.bottom, Theme.Spacing.sm)
        }
        .padding(.top, Theme.Spacing.sm)
        .background(.bar)
    }
}

/// 一覧やふきだしの横に置くコーチの顔（ドット絵）。
private struct CoachAvatar: View {
    var body: some View {
        Canvas { context, size in
            let sprite = PixelCharacterArt.coachHead(blinking: false)
            let dot = max(1, (size.width / CGFloat(sprite.width)).rounded(.down))
            let w = CGFloat(sprite.width) * dot
            let h = CGFloat(sprite.height) * dot
            context.drawPixels(
                sprite,
                at: CGPoint(x: ((size.width - w) / 2).rounded(), y: ((size.height - h) / 2).rounded()),
                dot: dot,
                palette: .make(skin: PixelCharacterRenderer.coachSkin)
            )
        }
        .frame(width: 36, height: 36)
        .background(Theme.bg2, in: Circle())
        .accessibilityHidden(true)
    }
}
