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

    /// アプリ内で Apple カレンダー連携を使うか（OS 許可とは別のスイッチ）。
    /// 設定の「連携を解除」で false にすると、OS 許可は残したまま週プランナーから予定を非表示にする。
    /// OS 許可自体の取り消しは iOS 設定 → プライバシー から。
    var isEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "gymnee.appleCalendarEnabled") }
    }

    /// 連携中（OS 許可あり かつ アプリ内で有効）。
    var isActive: Bool { authorized && isEnabled }

    init() {
        if let v = UserDefaults.standard.object(forKey: "gymnee.appleCalendarEnabled") as? Bool { isEnabled = v }
        refreshAuthorization()
    }

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

    /// プロバイダ非依存イベントで返す（Google と統合して週プランナーで扱うため）。
    /// アプリ内連携がオフ（isEnabled=false）なら空を返す。
    func calendarEvents(from: Date, to: Date) -> [CalendarEvent] {
        guard isEnabled else { return [] }
        return events(from: from, to: to).map { ev in
            CalendarEvent(
                id: "apple:\(ev.eventIdentifier ?? UUID().uuidString)",
                title: ev.title ?? "予定",
                start: ev.startDate,
                end: ev.endDate ?? ev.startDate,
                isAllDay: ev.isAllDay,
                source: .apple
            )
        }
    }
}
