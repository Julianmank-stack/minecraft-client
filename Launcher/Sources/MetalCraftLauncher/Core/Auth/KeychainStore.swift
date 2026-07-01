import Foundation
import Security

/// Secure token storage backed by the macOS Keychain.
/// Raw passwords are never handled by this app; only OAuth tokens are stored.
final class KeychainStore {
    private let service = "dev.metalcraft.launcher"

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            if case let .status(s) = self { return "Keychain error (\(s))" }
            return nil
        }
    }

    func save(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Typed helpers

    func saveString(_ value: String, forKey key: String) throws {
        try save(Data(value.utf8), forKey: key)
    }

    func loadString(forKey key: String) -> String? {
        load(forKey: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    func saveCodable<T: Encodable>(_ value: T, forKey key: String) throws {
        try save(JSONEncoder().encode(value), forKey: key)
    }

    func loadCodable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        load(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
