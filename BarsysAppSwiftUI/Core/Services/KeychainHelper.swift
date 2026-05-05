//
//  KeychainHelper.swift
//  BarsysAppSwiftUI
//
//  1:1 port of UIKit
//  `BarsysApp/Helpers/KeychainClass/KeychainHelper.swift`.
//
//  Secure wrapper around the iOS Keychain for sensitive values
//  (`session_token`, `userId`, `user_email`, `user_phone`, etc.) that
//  must NOT live in plain-text `UserDefaults`. Used by
//  `UserDefaultsClass` exactly the way UIKit does — same key strings,
//  same `kSecAttrAccessibleAfterFirstUnlock` accessibility class — so
//  data written by either build is readable by the other when sharing
//  the same bundle id.
//
//  Thread-safety: no mutable state, all methods are pure wrappers
//  around the `Security` framework, safe to call from any thread.
//

import Foundation
import Security

final class KeychainHelper: @unchecked Sendable {

    /// Singleton — matches UIKit's `KeychainHelper.shared` so call-site
    /// usage (`KeychainHelper.shared.save(...)`) is identical.
    static let shared = KeychainHelper()

    private init() {}

    // MARK: - Save

    /// Persist `value` under `key`. Existing items are deleted first
    /// (Keychain doesn't overwrite — `SecItemAdd` returns
    /// `errSecDuplicateItem` if the account already exists).
    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete(forKey: key)
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrAccount as String:     key,
            kSecValueData as String:       data,
            kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Get

    /// Retrieve a UTF-8 string previously written via `save`. Returns
    /// `nil` if the key is missing or the stored data isn't valid UTF-8.
    func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  key,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    // MARK: - Delete

    /// Remove a single key. Returns `true` on success or "not found"
    /// (so chained deletes don't bail out for keys that were never set).
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Bulk delete — matches UIKit's `deleteAll(forKeys:)` so the
    /// `clearAll()` flow on logout / delete-account / session-expired
    /// is one liner per keychain.
    @discardableResult
    func deleteAll(forKeys keys: [String]) -> Bool {
        var success = true
        for key in keys {
            if !delete(forKey: key) { success = false }
        }
        return success
    }
}
