import Foundation
import Observation

/// アプリ全体のエラー通知（§7 堅牢性）。保存失敗などをユーザーに提示するための集約点。
/// View 側は RootView の .alert で購読し、各書込パスは `report` を呼ぶ。
@MainActor
@Observable
final class AppErrorCenter {
    var message: String?
    var isPresented: Bool {
        get { message != nil }
        set { if !newValue { message = nil } }
    }

    func report(_ error: Error) {
        message = (error as NSError).localizedDescription
    }

    func report(_ text: String) {
        message = text
    }
}
