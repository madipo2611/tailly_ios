import Combine
import Foundation
import Security

final class SessionStore: ObservableObject {
    @Published private(set) var isRestoring = true
    @Published private(set) var isAuthenticated = false
    private let accessKey = "ru.tailly.ios.access-token"
    private let refreshKey = "ru.tailly.ios.refresh-token"

    var accessToken: String? { Keychain.value(for: accessKey) }
    var refreshToken: String? { Keychain.value(for: refreshKey) }

    func restore() async { isAuthenticated = accessToken != nil; isRestoring = false }
    func save(accessToken: String, refreshToken: String) { Keychain.save(accessToken, for: accessKey); Keychain.save(refreshToken, for: refreshKey); isAuthenticated = true }
    func replaceAccessToken(_ token: String) { Keychain.save(token, for: accessKey) }
    func signOut() { Keychain.remove(accessKey); Keychain.remove(refreshKey); isAuthenticated = false }
}

enum Keychain {
    static func save(_ value: String, for key: String) { remove(key); SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key, kSecValueData: Data(value.utf8)] as CFDictionary, nil) }
    static func value(for key: String) -> String? { var result: CFTypeRef?; let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key, kSecReturnData: true] as CFDictionary, &result); guard status == errSecSuccess, let data = result as? Data else { return nil }; return String(data: data, encoding: .utf8) }
    static func remove(_ key: String) { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary) }
}
