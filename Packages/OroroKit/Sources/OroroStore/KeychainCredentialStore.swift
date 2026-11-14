import Foundation
import OroroCore
import Security

/// Stores the single set of credentials as one generic-password keychain item
/// (account = email, data = password).
public final class KeychainCredentialStore: CredentialStoring {
    public struct KeychainError: Error, Equatable {
        public let status: OSStatus
    }

    private let service: String

    public init(service: String = "com.dissimirall.Ororo-Player") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    public func load() -> Credentials? {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let email = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return Credentials(email: email, password: password)
    }

    public func save(_ c: Credentials) throws {
        try clear()
        var query = baseQuery
        query[kSecAttrAccount as String] = c.email
        query[kSecValueData as String] = Data(c.password.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
