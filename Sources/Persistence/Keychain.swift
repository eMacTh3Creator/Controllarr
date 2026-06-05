//
//  Keychain.swift
//  Controllarr
//
//  Minimal wrapper around Security.framework keychain APIs for legacy
//  credential migration. Public ad-hoc builds must not trigger Keychain
//  prompts during normal app use, so reads explicitly skip authentication UI.
//

import Foundation
import Security

public enum Keychain {

    private static let service = "com.controllarr.credentials"

    /// Store `value` for `key`. Overwrites any existing value.
    public static func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseAuthenticationUI: kSecUseAuthenticationUISkip,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[Controllarr] Keychain set failed for \(key): \(status)")
        }
    }

    /// Retrieve the string stored under `key`, or nil if none.
    public static func get(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
            kSecUseAuthenticationUI: kSecUseAuthenticationUISkip,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Remove the entry for `key`.
    public static func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecUseAuthenticationUI: kSecUseAuthenticationUISkip,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Convenience keys
    public static let webUIPasswordKey = "webui_password"
}
