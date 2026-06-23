import Foundation
import Security

/// 機微情報（認証トークン）の Keychain 保存。UserDefaults と違い iTunes/Finder バックアップや
/// 他アプリから読めず、refresh_token 流出によるセッション乗っ取りを防ぐ。
/// アクセス制御は AfterFirstUnlockThisDeviceOnly（起動時の自動リフレッシュは可・端末外へは出ない）。
enum Keychain {
    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
