import Foundation

/// 参加したルームの資格情報。
///
/// トークンは**平文をDBに置かない**（11_API設計.md §2）。
/// 端末ではキーチェーンに入れ、SwiftData には持たせない。
struct RoomCredentials: Equatable {
    let roomId: UUID
    let memberId: UUID
    let token: String
}

protocol CredentialStoring: AnyObject {
    func load() -> RoomCredentials?
    func save(_ credentials: RoomCredentials) throws
    func clear() throws
}

/// キーチェーン。端末が施錠されている間は読めないが、
/// バックグラウンドの送信は復帰後で構わないので `AfterFirstUnlock` で足りる。
final class KeychainCredentialStore: CredentialStoring {

    private let service: String
    private let account = "room"

    init(service: String = "com.non-migi.RailAngyerApp.credentials") {
        self.service = service
    }

    func load() -> RoomCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }

        return RoomCredentials(roomId: stored.roomId, memberId: stored.memberId, token: stored.token)
    }

    func save(_ credentials: RoomCredentials) throws {
        let data = try JSONEncoder().encode(Stored(roomId: credentials.roomId,
                                                   memberId: credentials.memberId,
                                                   token: credentials.token))
        try clear()

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private struct Stored: Codable {
        let roomId: UUID
        let memberId: UUID
        let token: String
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "キーチェーンの操作に失敗しました（\(status)）" }
    }
}

/// テスト用。キーチェーンはシミュレータでも共有されるため、検証では触らない
final class InMemoryCredentialStore: CredentialStoring {
    private var stored: RoomCredentials?

    init(_ initial: RoomCredentials? = nil) { stored = initial }

    func load() -> RoomCredentials? { stored }
    func save(_ credentials: RoomCredentials) throws { stored = credentials }
    func clear() throws { stored = nil }
}
