import SwiftUI

/// 戻せない削除の確認（#168）。どの入口でも同じ形で出す。
///
/// - 文面は `DeletionCopy`（消える中身を数で書く）
/// - 投稿の取り下げだけで済む場合は、同じ確認の中に「非公開にする」を並べる
/// - スワイプの削除は `allowsFullSwipe: false` にして、払い切るだけでは消さない（押すとこの確認が出る）
struct DeletionRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var destructiveLabel = "削除"
    let onDelete: @MainActor () -> Void
    /// 記録は残して投稿だけ取り下げる（公開済みのときだけ）。
    var makePrivate: (@MainActor () -> Void)?
}

private struct DeletionConfirmationModifier: ViewModifier {
    @Binding var request: DeletionRequest?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            request?.title ?? "",
            isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
            titleVisibility: .visible,
            presenting: request
        ) { r in
            Button(r.destructiveLabel, role: .destructive) {
                r.onDelete()
                request = nil
            }
            if let makePrivate = r.makePrivate {
                Button(DeletionCopy.makePrivateLabel) {
                    makePrivate()
                    request = nil
                }
            }
            Button("キャンセル", role: .cancel) { request = nil }
        } message: { r in
            Text(r.message)
        }
    }
}

extension View {
    /// `request` に値を入れると確認を出す。決めたら nil に戻る。
    func deletionConfirmation(_ request: Binding<DeletionRequest?>) -> some View {
        modifier(DeletionConfirmationModifier(request: request))
    }
}

#if DEBUG
/// `-gymneeScreen delete-confirm` / `account-delete`: 削除の確認を直接出す（simctl はタップできないため）。
struct DebugDeletionPreview: View {
    let kind: String
    @State private var request: DeletionRequest?

    var body: some View {
        Color.clear
            .deletionConfirmation($request)
            .onAppear {
                switch kind {
                case "account-delete":
                    let copy = DeletionCopy.accountDeletion(isSignedIn: true)
                    request = DeletionRequest(title: copy.title, message: copy.message, destructiveLabel: copy.confirmLabel, onDelete: {})
                default:
                    request = DeletionRequest(
                        title: DeletionCopy.workoutTitle,
                        message: DeletionCopy.workoutMessage(.init(exercises: 3, sets: 9, isPublished: true, reactions: 2, hasPhoto: false)),
                        onDelete: {},
                        makePrivate: {}
                    )
                }
            }
    }
}
#endif
