import Foundation
import Security

/// Generic keychain wrapper. Currently unused — all third-party API keys
/// (Anthropic, ElevenLabs, Deepgram) live server-side in Supabase secrets and
/// are never sent to the client. Kept as a building block in case future
/// device-specific secrets need to be stored locally.
public enum KeychainStore {
    public enum Account: String, CaseIterable {
        // Reserved for future use. No accounts currently in production.
        case _placeholder = "_PLACEHOLDER"
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
        let data = Data(value.utf8)
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
