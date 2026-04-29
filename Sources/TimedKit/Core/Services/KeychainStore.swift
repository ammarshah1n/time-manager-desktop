import Foundation
import Security

/// Generic keychain wrapper. Used for local device data that is sensitive
/// at rest — content derived from the user's email/calendar/observations
/// must not live in UserDefaults plaintext (`~/Library/Preferences/*.plist`
/// is unencrypted and readable by any process running under the same UID).
/// Third-party API keys (Anthropic, ElevenLabs, Deepgram) live server-side
/// in Supabase secrets and are never sent to the client.
public enum KeychainStore {
    public enum Account: String, CaseIterable {
        /// JSON-encoded `DishMeUpSnapshot`. Contains task titles + reasons
        /// generated from the user's mail/calendar corpus, so cannot live
        /// in UserDefaults.
        case dishMeUpSnapshot = "DISH_ME_UP_SNAPSHOT"
    }

    enum StoreError: Error {
        case invalidString
        case keychain(OSStatus)
    }

    private static let service = "com.timed.app.keys"
    private static let migrationFlagKey = "keychainStore.purgedClientSecrets.v2"

    static func string(for account: Account) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func setString(_ value: String, for account: Account) throws {
        try setData(Data(value.utf8), for: account)
    }

    /// Read raw bytes for an account, or `nil` if absent.
    public static func data(for account: Account) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    public static func setData(_ data: Data, for account: Account) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StoreError.keychain(status) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
    }

    public static func remove(_ account: Account) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(q as CFDictionary)
    }

    /// Idempotent purge of historical client-side API keys. Called on app
    /// launch — strips any Anthropic / ElevenLabs / Deepgram keys that may
    /// linger from older builds, plus any matching @AppStorage entries.
    /// Production architecture proxies all third-party APIs through Supabase
    /// Edge Functions, so the client never holds these keys.
    @discardableResult
    public static func migrateLegacyKeysIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationFlagKey) { return false }

        let legacyServices = ["com.timed.app.keys", "com.ammarshahin.timed.keys"]
        let legacyAccounts = ["ANTHROPIC_API_KEY", "ELEVENLABS_API_KEY", "DEEPGRAM_API_KEY"]
        for svc in legacyServices {
            for account in legacyAccounts {
                let q: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: svc,
                    kSecAttrAccount as String: account,
                ]
                SecItemDelete(q as CFDictionary)
            }
        }
        let legacyDefaultsKeys = ["anthropic_api_key", "elevenlabs_api_key"]
        for key in legacyDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: migrationFlagKey)
        return true
    }
}
