import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum AppLockError: LocalizedError, Equatable {
    case notConfigured
    case wrongPassword
    case passwordTooShort
    case keychain(OSStatus)
    case biometricUnavailable
    case biometricFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: AppLocalization.string( "尚未设置 App 密码")
        case .wrongPassword: AppLocalization.string( "当前密码不正确")
        case .passwordTooShort: AppLocalization.string( "密码至少需要 6 位")
        case .keychain: AppLocalization.string( "无法访问系统钥匙串")
        case .biometricUnavailable: AppLocalization.string( "此设备暂时无法使用 Face ID 或 Touch ID")
        case .biometricFailed: AppLocalization.string( "生物识别未通过")
        }
    }
}

private struct AppLockCredential: Codable {
    let salt: Data
    let digest: Data
    let rounds: Int
}

struct AppLockCredentialStore {
    private let service: String
    private let account: String
    private let rounds = 80_000

    init(
        service: String = "com.ian.MultiCurrencyLedger.appLock",
        account: String = "primary"
    ) {
        self.service = service
        self.account = account
    }

    func hasCredential() -> Bool {
        (try? credentialExists()) == true
    }

    private func credentialExists() throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw AppLockError.keychain(status)
        }
    }

    func setPassword(_ password: String, currentPassword: String? = nil) throws {
        guard password.count >= 6 else { throw AppLockError.passwordTooShort }
        let isConfigured = try credentialExists()
        if isConfigured {
            guard let currentPassword, try verify(currentPassword) else { throw AppLockError.wrongPassword }
        }
        var salt = Data(count: 24)
        let saltCount = salt.count
        let randomStatus = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, saltCount, $0.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw AppLockError.keychain(randomStatus) }
        let credential = AppLockCredential(
            salt: salt,
            digest: Self.derive(password: password, salt: salt, rounds: rounds),
            rounds: rounds
        )
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        let status: OSStatus
        if isConfigured {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppLockError.keychain(status) }
    }

    func verify(_ password: String) throws -> Bool {
        let credential = try readCredential()
        let candidate = Self.derive(password: password, salt: credential.salt, rounds: credential.rounds)
        return Self.constantTimeEqual(candidate, credential.digest)
    }

    func remove(currentPassword: String) throws {
        guard try credentialExists() else { throw AppLockError.notConfigured }
        guard try verify(currentPassword) else { throw AppLockError.wrongPassword }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppLockError.keychain(status)
        }
    }

    private func readCredential() throws -> AppLockCredential {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw AppLockError.notConfigured }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppLockError.keychain(status)
        }
        return try JSONDecoder().decode(AppLockCredential.self, from: data)
    }

    private static func derive(password: String, salt: Data, rounds: Int) -> Data {
        let passwordData = Data(password.utf8)
        var value = Data(SHA256.hash(data: salt + passwordData))
        if rounds > 1 {
            for _ in 1..<rounds {
                value = Data(SHA256.hash(data: value + salt + passwordData))
            }
        }
        return value
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8.zero) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

struct BiometricAuthenticator {
    func availability() -> (available: Bool, name: String) {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let name: String
        switch context.biometryType {
        case .faceID: name = "Face ID"
        case .touchID: name = "Touch ID"
        case .opticID: name = "Optic ID"
        case .none: name = AppLocalization.string( "生物识别")
        @unknown default: name = AppLocalization.string( "生物识别")
        }
        return (available, name)
    }

    func authenticate() async throws {
        let context = LAContext()
        context.localizedCancelTitle = AppLocalization.string( "使用密码")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AppLockError.biometricUnavailable
        }
        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: AppLocalization.string( "解锁你的账本")
            ) else { throw AppLockError.biometricFailed }
        } catch {
            throw AppLockError.biometricFailed
        }
    }
}

extension Notification.Name {
    static let appLockConfigurationChanged = Notification.Name("appLockConfigurationChanged")
}

@MainActor
final class AppLockManager: ObservableObject {
    @Published private(set) var isLocked: Bool
    @Published private(set) var isConfigured: Bool
    @Published var errorMessage: String?

    private let store: AppLockCredentialStore
    private let biometrics: BiometricAuthenticator

    init(
        store: AppLockCredentialStore = AppLockCredentialStore(),
        biometrics: BiometricAuthenticator = BiometricAuthenticator()
    ) {
        self.store = store
        self.biometrics = biometrics
        let configured = store.hasCredential()
        isConfigured = configured
        isLocked = configured
    }

    var biometricName: String { biometrics.availability().name }
    var canUseBiometrics: Bool {
        biometrics.availability().available
            && UserDefaults.standard.object(forKey: "appLockBiometricsEnabled") as? Bool != false
    }

    func unlock(password: String) {
        do {
            guard try store.verify(password) else { throw AppLockError.wrongPassword }
            errorMessage = nil
            isLocked = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unlockWithBiometrics() async {
        do {
            try await biometrics.authenticate()
            errorMessage = nil
            isLocked = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func lockForPrivacyIfNeeded() {
        guard isConfigured else { return }
        let shouldLock = UserDefaults.standard.object(forKey: "appLockOnBackground") as? Bool ?? true
        if shouldLock { isLocked = true }
    }

    func refreshConfiguration(lockIfNeeded: Bool = false) {
        isConfigured = store.hasCredential()
        if !isConfigured { isLocked = false }
        else if lockIfNeeded { isLocked = true }
    }
}
