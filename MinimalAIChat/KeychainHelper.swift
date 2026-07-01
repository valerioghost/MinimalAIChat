import Foundation
import Security

// MARK: - KeychainHelper
//
// A minimal, zero-dependency Keychain wrapper.
// All operations are synchronous and run on the calling thread.
// Compatible with iOS 15+.

final class KeychainHelper {

    // Shared singleton for convenience
    static let shared = KeychainHelper()
    private init() {}

    // MARK: - Public API

    /// Saves (or updates) a UTF-8 string value for the given key.
    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first so SecItemAdd always succeeds
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      bundleID,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Reads and returns the UTF-8 string stored for the given key, or `nil`.
    func read(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  bundleID,
            kSecAttrAccount as String:  key,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Deletes the item stored for the given key. No-op if absent.
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  bundleID,
            kSecAttrAccount as String:  key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Private

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.example.MinimalAIChat"
    }
}
