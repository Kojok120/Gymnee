import SwiftUI
import SwiftData
import CoreLocation

/// ジム自己登録（§6.4）。現在地を取り込み、リバースジオコーディングで店名/住所を自動補完する。
struct AddGymView: View {
    let userId: UUID
    /// 初期表示する名前（チェックインの「近くに無い」フォールバックから渡せる）。
    var suggestedName: String? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @Environment(LocalSyncEngine.self) private var sync
    @Environment(AppErrorCenter.self) private var errors

    @State private var name = ""
    @State private var chain = ""
    @State private var address = ""
    @State private var captureLocation = true
    @State private var geocoding = false
    @State private var didPrefill = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("例: エニタイム◯◯店", text: $name)
                        if geocoding { ProgressView().controlSize(.small) }
                    }
                } header: {
                    Text("ジム名")
                } footer: {
                    if !address.isEmpty {
                        Label(address, systemImage: "mappin.and.ellipse").font(.caption2)
                    }
                }
                Section("チェーン（任意）") {
                    TextField("例: Anytime Fitness", text: $chain)
                }
                Section {
                    Toggle("現在地を登録する", isOn: $captureLocation)
                    if captureLocation {
                        if let loc = location.current {
                            LabeledContent("現在地") {
                                Text(String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                Task { await reverseGeocode(force: true) }
                            } label: {
                                Label("現在地から店名・住所を取得", systemImage: "location.magnifyingglass")
                            }
                        } else {
                            Text("位置情報を取得中… 許諾が必要です。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("現在地を登録すると店名・住所を自動補完し、次回チェックイン時に近くのジムとして自動提案されます。")
                }
            }
            .navigationTitle("ジムを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let suggestedName, name.isEmpty { name = suggestedName }
                if captureLocation { location.requestWhenInUse() }
            }
            .task(id: location.current?.timestamp) {
                await reverseGeocode(force: false)
            }
        }
    }

    /// 現在地を逆ジオコーディングして店名/住所を補完。force=false のときは未入力欄のみ埋める。
    private func reverseGeocode(force: Bool) async {
        guard captureLocation, let loc = location.current else { return }
        if !force && didPrefill { return }
        geocoding = true
        defer { geocoding = false }
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(loc).first else { return }
        didPrefill = true
        let placeName = placemark.name ?? placemark.areasOfInterest?.first
        let parts = [placemark.administrativeArea, placemark.locality, placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0 }
        address = parts.joined()
        if let placeName, (force || name.trimmingCharacters(in: .whitespaces).isEmpty) {
            name = placeName
        }
    }

    private func save() {
        let loc = captureLocation ? location.current : nil
        let gym = Gym(
            name: name.trimmingCharacters(in: .whitespaces),
            chain: chain.isEmpty ? nil : chain,
            address: address.isEmpty ? nil : address,
            lat: loc?.coordinate.latitude,
            lng: loc?.coordinate.longitude,
            source: .user,
            createdBy: userId
        )
        context.insert(gym)
        do {
            try context.save()
        } catch {
            errors.report("ジムを保存できませんでした。\(error.localizedDescription)")
            return
        }
        sync.enqueue(PendingChange(entity: "gyms", recordId: gym.id, operation: .upsert, updatedAt: gym.updatedAt))
        dismiss()
    }
}
