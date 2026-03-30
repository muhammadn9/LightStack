import Foundation
import Security

/// Thin wrapper around the iOS Keychain for storing sensitive string values.
/// Credentials stored here do not appear in memory dumps, crash reports,
/// or observable SwiftUI state — unlike plain properties on ObservableObjects.
struct KeychainService {

    private static let service = Bundle.main.bundleIdentifier ?? "com.lightstack.app"

    // MARK: - Public Interface

    /// Save or overwrite a string value in the Keychain.
    /// Returns true on success.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first so SecItemAdd always operates on a clean slot
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            // Item is accessible when the device is unlocked; not backed up to iCloud
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Load a string value from the Keychain.
    /// Returns nil if the item does not exist or cannot be decoded.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }

        return string
    }

    /// Delete a value from the Keychain.
    /// Returns true on success or if the item did not exist.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
