import Foundation

/// プロバイダ非依存のカレンダー予定（Apple EventKit / Google Calendar を統一して扱う）。
/// 週プランナーは本型の配列を表示・AI計画入力に使い、出どころ(source)で見た目だけ分ける。
struct CalendarEvent: Identifiable, Hashable {
    enum Source: String, Hashable { case apple, google }

    /// プロバイダ横断で一意（"apple:<id>" / "google:<id>"）。
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let source: Source
}
