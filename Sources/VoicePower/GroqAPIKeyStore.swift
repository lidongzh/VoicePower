import Foundation
import Security

struct GroqAPIKeyStore: Sendable {
    private static let service = "local.voicepower.groq"
    private static let account = "default"

    func load() throws -> String? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw VoicePowerError.keychainOperationFailed(operation: "load Groq API key", details: message(for: status))
        }
    }

    func save(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try clear()
            return
        }

        let encoded = Data(trimmed.utf8)
        let status = SecItemCopyMatching(baseQuery() as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            let attributesToUpdate = [
                kSecValueData as String: encoded,
            ]
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw VoicePowerError.keychainOperationFailed(operation: "save Groq API key", details: message(for: updateStatus))
            }
        case errSecItemNotFound:
            var item = baseQuery()
            item[kSecValueData as String] = encoded
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw VoicePowerError.keychainOperationFailed(operation: "save Groq API key", details: message(for: addStatus))
            }
        default:
            throw VoicePowerError.keychainOperationFailed(operation: "save Groq API key", details: message(for: status))
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VoicePowerError.keychainOperationFailed(operation: "clear Groq API key", details: message(for: status))
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    private func message(for status: OSStatus) -> String {
        if let error = SecCopyErrorMessageString(status, nil) as String? {
            return error
        }

        return "OSStatus \(status)"
    }
}
