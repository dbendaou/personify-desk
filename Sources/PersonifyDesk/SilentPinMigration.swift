import Foundation
import PersonifyCore
import Security

/// One attempt to copy pairing codes out of the login Keychain without ever showing a prompt.
/// If macOS would ask for a password, the call fails and the app keeps the editable default instead.
enum SilentPinMigration {
    private static let service = "com.local.personifydesk.pairing-pin"
    private static let flag = "personifydesk.pinStoreLocal"

    static func migrateOnce(into store: DefaultsPinStore, defaults: UserDefaults = .standard) {
        if defaults.object(forKey: flag) != nil { return }
        defaults.set(true, forKey: flag)
        guard let copied = copyWithoutPrompt() else { return }
        store.importMigrated(copied)
        deleteWithoutPrompt()
    }

    private static func copyWithoutPrompt() -> [String: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [:] }
        if status == errSecInteractionNotAllowed || status != errSecSuccess { return nil }
        let rows: [NSDictionary]
        if let dictionaries = item as? [NSDictionary] {
            rows = dictionaries
        } else if let array = item as? NSArray {
            rows = array.compactMap { $0 as? NSDictionary }
        } else if let one = item as? NSDictionary {
            rows = [one]
        } else {
            rows = []
        }
        var values: [String: String] = [:]
        for row in rows {
            guard let deviceID = row[kSecAttrAccount as String] as? String,
                  let data = row[kSecValueData as String] as? Data,
                  let pin = String(data: data, encoding: .utf8),
                  !pin.isEmpty
            else { continue }
            values[deviceID] = pin
        }
        return values
    }

    private static func deleteWithoutPrompt() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
