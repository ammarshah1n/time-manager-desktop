import Foundation
import Security

enum KeychainStore {
    enum Account: String, CaseIterable {
        case deepgramAPIKey = "DEEPGRAM_API_KEY"
        case anthropicAPIKey = "ANTHROPIC_API_KEY"
        case elevenlabsAPIKey = "ELEVENLABS_API_KEY"

        var legacyAppStorageKey: String? {
            switch self {
            case .deepgramAPIKey: nil
            case .anthropicAPIKey: "anthropic_api_key"
            case .elevenlabsAPIKey: "elevenlabs_api_key"
            }
        }
    }

    enum StoreError: Error {
        case invalidString
        case keychain(OSStatus)
    }

    private static let service = "com.ammarshahin.timed.keys"
    private static let migrationFlagKey = "keychainStore.migratedFromAppStorage.v1"

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
        let update: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StoreError.keychain(status) }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
    }

    @discardableResult
    static func migrateLegacyKeysIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationFlagKey) { return false }

        var migrated = false
        for account in Account.allCases {
            guard let legacyKey = account.legacyAppStorageKey,
                  let legacyValue = defaults.string(forKey: legacyKey),
                  !legacyValue.isEmpty,
                  string(for: account).isEmpty else {
                continue
            }
            do {
                try setString(legacyValue, for: account)
                defaults.removeObject(forKey: legacyKey)
                migrated = true
            } catch {
                continue
            }
        }
        defaults.set(true, forKey: migrationFlagKey)
        return migrated
    }
}
