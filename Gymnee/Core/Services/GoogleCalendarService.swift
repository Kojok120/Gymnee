import Foundation
import Observation
import UIKit
import GoogleSignIn

/// Google カレンダー連携（GoogleSignIn で認証 ＋ Calendar REST を自前で叩く）。
/// 読み取り（予定表示・AI計画入力）と書き込み（計画作成時に予定追加）。スコープは calendar.events。
///
/// クライアントID（Info.plist `GIDClientID` = xcconfig `GOOGLE_IOS_CLIENT_ID`）が未設定なら
/// `isConfigured == false` となり、設定画面は「未設定」表示で連携ボタンは無効。
/// Google Cloud で iOS OAuth クライアントを作成し、値を Secrets.*.xcconfig に入れると有効化される。
@MainActor
@Observable
final class GoogleCalendarService {
    /// カレンダーの読み書きスコープ（events 単位）。
    static let scope = "https://www.googleapis.com/auth/calendar.events"

    /// Google にサインイン済みか（カレンダー権限の有無に関わらず）。連携解除ボタンの表示に使う。
    private(set) var isSignedIn = false
    /// カレンダー権限(calendar.events)まで付与され、読み書きできる状態か。
    private(set) var isConnected = false
    private(set) var email: String?
    private(set) var lastError: String?

    /// iOS OAuth クライアントID。空なら未設定（連携不可）。
    private let clientID: String
    var isConfigured: Bool { !clientID.isEmpty }

    init() {
        clientID = (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String) ?? ""
        if !clientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    /// 起動時に前回のサインインを復元（カレンダースコープ付与済みなら連携中とみなす）。
    func restore() {
        guard isConfigured else { return }
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
            Task { @MainActor in self?.applyUser(user) }
        }
    }

    /// OAuth コールバック URL を処理（GymneeApp の onOpenURL から呼ぶ）。
    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// 連携（サインイン＋カレンダースコープ要求）。
    func connect() async {
        guard isConfigured else { lastError = "Google クライアントID未設定（Secrets に GOOGLE_IOS_CLIENT_ID を設定）"; return }
        guard let presenter = Self.topViewController() else { lastError = "表示元が見つかりません"; return }
        let outcome: Result<GIDSignInResult, Error> = await withCheckedContinuation { cont in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: [Self.scope]) { result, error in
                if let result { cont.resume(returning: .success(result)) }
                else { cont.resume(returning: .failure(error ?? URLError(.userCancelledAuthentication))) }
            }
        }
        switch outcome {
        case .success(let result):
            applyUser(result.user)
            lastError = isConnected ? nil : "カレンダーの権限が許可されませんでした"
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    /// 連携解除（ローカルのサインアウトのみ。サーバー側のトークン失効は disconnect で）。
    func disconnect() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        isConnected = false
        email = nil
        lastError = nil
    }

    private func applyUser(_ user: GIDGoogleUser?) {
        guard let user else { isSignedIn = false; isConnected = false; email = nil; return }
        isSignedIn = true
        isConnected = user.grantedScopes?.contains(Self.scope) ?? false
        email = user.profile?.email
    }

    // MARK: - Calendar REST

    /// 有効なアクセストークン（必要なら更新）。
    private func accessToken() async -> String? {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return nil }
        return await withCheckedContinuation { cont in
            user.refreshTokensIfNeeded { refreshed, _ in
                cont.resume(returning: refreshed?.accessToken.tokenString)
            }
        }
    }

    /// 指定期間の予定を取得（読み取り）。未連携・失敗時は空配列。
    func events(from: Date, to: Date) async -> [CalendarEvent] {
        guard isConnected, let token = await accessToken() else { return [] }
        guard var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events") else { return [] }
        let iso = ISO8601DateFormatter()
        comps.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: from)),
            URLQueryItem(name: "timeMax", value: iso.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return Self.parseEvents(data)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// 予定を追加（書き込み）。計画作成時に呼ぶ。成功で true。
    @discardableResult
    func addEvent(title: String, start: Date, end: Date, allDay: Bool) async -> Bool {
        guard isConnected, let token = await accessToken() else { return false }
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any]
        if allDay {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = .current
            body = ["summary": title,
                    "start": ["date": df.string(from: start)],
                    "end": ["date": df.string(from: end)]]
        } else {
            let iso = ISO8601DateFormatter()
            body = ["summary": title,
                    "start": ["dateTime": iso.string(from: start)],
                    "end": ["dateTime": iso.string(from: end)]]
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - parsing / helpers

    private static let isoParsers: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, fractional]
    }()

    private static func parseISO(_ s: String) -> Date? {
        for p in isoParsers { if let d = p.date(from: s) { return d } }
        return nil
    }

    private static func parseEvents(_ data: Data) -> [CalendarEvent] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else { return [] }
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.timeZone = .current
        return items.compactMap { item -> CalendarEvent? in
            let rawId = item["id"] as? String ?? UUID().uuidString
            let title = (item["summary"] as? String) ?? "予定"
            guard let startObj = item["start"] as? [String: Any],
                  let endObj = item["end"] as? [String: Any] else { return nil }
            if let sdt = startObj["dateTime"] as? String, let start = parseISO(sdt) {
                let end = (endObj["dateTime"] as? String).flatMap(parseISO) ?? start
                return CalendarEvent(id: "google:\(rawId)", title: title, start: start, end: end, isAllDay: false, source: .google)
            }
            if let sd = startObj["date"] as? String, let start = dayFmt.date(from: sd) {
                let end = (endObj["date"] as? String).flatMap { dayFmt.date(from: $0) } ?? start
                return CalendarEvent(id: "google:\(rawId)", title: title, start: start, end: end, isAllDay: true, source: .google)
            }
            return nil
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
