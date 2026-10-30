import Foundation
import Security

/// APIキーなどの秘密は Keychain にだけ置く。ファイル・ログ・画面には出さない。
enum Keychain {
    private static let service = "app.cooltime.credentials"

    private static func query(_ account: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account.uuidString]
    }

    static func set(_ secret: String, for account: UUID) {
        delete(account)
        var q = query(account)
        q[kSecValueData as String] = Data(secret.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ account: UUID) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func has(_ account: UUID) -> Bool { get(account) != nil }

    static func delete(_ account: UUID) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
