import Foundation
import EventKit
import Observation

/// Apple カレンダー（EventKit）連携（§6.5）。予定を読み取り、ワークアウト計画に重ねて表示する。
/// 書き込みは行わず読み取りのみ（予定を避けて計画するのが目的）。
@MainActor
@Observable
final class CalendarService {
    private let store = EKEventStore()
    private(set) var authorized = false

    init() { refreshAuthorization() }

    private func refreshAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorized = (status == .fullAccess || status == .authorized)
    }

    /// アクセス許可をリクエスト（iOS17+ はフルアクセス）。
    func requestAccess() async {
        if #available(iOS 17.0, *) {
            authorized = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            authorized = (try? await store.requestAccess(to: .event)) ?? false
        }
    }

    /// 指定期間の予定（終日含む）を開始時刻順で返す。
    func events(from: Date, to: Date) -> [EKEvent] {
        guard authorized else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}
