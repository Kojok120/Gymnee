import SwiftUI
import SwiftData

/// チェックイン（来店）の編集（§6.11）。メモ・来店日時・公開範囲・合トレ相手を後から変更できる。
struct CheckInEditView: View {
    @Bindable var visit: Visit
    /// 現在の公開範囲（この来店の feed_item の visibility。未公開なら .private）。
    let currentVisibility: Visibility

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(LocalSyncEngine.self) private var sync
    @Query private var follows: [Follow]
    @Query private var profiles: [Profile]
    @State private var visibility: Visibility
    /// 合トレ相手。フレンド選択なら実 userId、手入力ならランダム UUID を id に持つ。
    @State private var partners: [CheckInView.PartnerDraft]
    @State private var newPartner = ""

    init(visit: Visit, currentVisibility: Visibility) {
        self.visit = visit
        self.currentVisibility = currentVisibility
        _visibility = State(initialValue: currentVisibility)
        _partners = State(initialValue: visit.partners.map {
            CheckInView.PartnerDraft(id: $0.partnerUserId, name: $0.partnerDisplayName ?? "ユーザー")
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ジム") {
                    Label(visit.gym?.name ?? "ジム", systemImage: "building.2.fill")
                }
                Section("日時") {
                    DatePicker("記録日時", selection: $visit.visitedAt)
                }
                Section("メモ") {
                    TextField("今日の調子・メニューなど", text: noteBinding, axis: .vertical)
                        .lineLimit(2...5)
                }
                partnerSection
                Section {
                    Picker("公開範囲", selection: $visibility) {
                        ForEach(Visibility.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("公開範囲")
                } footer: {
                    Text("この投稿を誰に見せるか。既定値は設定で変更できます。")
                }
            }
            .navigationTitle("ジム活を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("保存") { save() }.bold() }
            }
        }
    }

    private var partnerSection: some View {
        Section("合トレ相手（任意）") {
            ForEach(partners) { p in
                Label(p.name, systemImage: "person.fill")
            }
            .onDelete { partners.remove(atOffsets: $0) }
            if !friendOptions.isEmpty {
                Menu {
                    ForEach(friendOptions) { f in
                        Button(f.name) { partners.append(f) }
                    }
                } label: {
                    Label("フレンドから追加", systemImage: "person.2.fill")
                }
            }
            HStack {
                TextField("名前を手入力", text: $newPartner)
                Button("追加") {
                    let trimmed = newPartner.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    partners.append(CheckInView.PartnerDraft(id: UUID(), name: trimmed))
                    newPartner = ""
                }
                .disabled(newPartner.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// フォロー中で、まだ追加していないフレンド（合トレ相手の候補）。
    private var friendOptions: [CheckInView.PartnerDraft] {
        guard let myId = auth.currentUserId else { return [] }
        let added = Set(partners.map(\.id))
        let nameById = Dictionary(profiles.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        return follows
            .filter { $0.followerId == myId }
            .map(\.followeeId)
            .filter { !added.contains($0) }
            .map { CheckInView.PartnerDraft(id: $0, name: nameById[$0] ?? "ユーザー") }
    }

    private var noteBinding: Binding<String> {
        Binding(get: { visit.note ?? "" }, set: { visit.note = $0.isEmpty ? nil : $0 })
    }

    private func save() {
        // 合トレ相手の差分を反映（partnerUserId をキーに追加/削除）。
        // enqueue は1件ごとに outbox 全書き出しが走るため、保存後にまとめて enqueueBatch する。
        var pending: [PendingChange] = []
        let draftIds = Set(partners.map(\.id))
        let originalIds = Set(visit.partners.map(\.partnerUserId))
        for p in visit.partners where !draftIds.contains(p.partnerUserId) {
            let id = p.id
            context.delete(p)
            pending.append(PendingChange(entity: "visit_partners", recordId: id, operation: .delete, updatedAt: .now))
        }
        for d in partners where !originalIds.contains(d.id) {
            let vp = VisitPartner(partnerUserId: d.id, partnerDisplayName: d.name, visit: visit)
            context.insert(vp)
            pending.append(PendingChange(entity: "visit_partners", recordId: vp.id, operation: .upsert, updatedAt: vp.updatedAt))
        }

        visit.updatedAt = .now
        visit.isDirty = true
        try? context.save()
        pending.append(PendingChange(entity: "visits", recordId: visit.id, operation: .upsert, updatedAt: visit.updatedAt))
        sync.enqueueBatch(pending)
        // 公開範囲の変更を feed_item へ反映（private＝非公開に戻す＝feed_item 削除、friends/public＝発行/更新）。
        if visibility != currentVisibility {
            FeedPublisher.setVisibility(visibility, forRefId: visit.id, type: .visit, userId: visit.userId,
                                        authorName: auth.session?.displayName, isPermanentAccount: auth.isPermanentAccount,
                                        context: context, sync: sync)
        }
        dismiss()
    }
}
