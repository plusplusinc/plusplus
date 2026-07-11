import Foundation
import Security
import PlusPlusKit

/// The real `TokenStore`: the GitHub access token in the iOS Keychain, as a
/// generic password keyed by service + account. `kSecAttrAccessibleAfterFirstUnlock`
/// so a background foreground-sync can read it before the user unlocks, but
/// it never leaves the device and isn't in any backup that syncs off-device.
///
/// The token is a GitHub App user-access token scoped (via the App's install)
/// to exactly the one routine repo — not a classic `repo`-scope OAuth token.
struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    init(service: String = "com.davidcole.plusplus.github", account: String = "access-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        // Upsert: try update first, fall back to add.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    enum KeychainError: Error {
        case status(OSStatus)
    }
}
