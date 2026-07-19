import Foundation

struct AccountCardIdentityStore {
    static let storageKey = "accountCardLastFourByID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastFour(for accountID: UUID) -> String? {
        let values = defaults.dictionary(forKey: Self.storageKey) as? [String: String]
        return values?[accountID.uuidString]
    }

    func setLastFour(_ rawValue: String?, for accountID: UUID) throws {
        let value = try Self.validated(rawValue)
        var values = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        values[accountID.uuidString] = value
        defaults.set(values, forKey: Self.storageKey)
    }

    func removeLastFour(for accountID: UUID) {
        var values = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        values.removeValue(forKey: accountID.uuidString)
        defaults.set(values, forKey: Self.storageKey)
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    static func sanitizedInput(_ value: String) -> String {
        let asciiDigits = CharacterSet(charactersIn: "0123456789")
        let digits = value.unicodeScalars.filter(asciiDigits.contains)
        return String(String.UnicodeScalarView(digits.prefix(4)))
    }

    static func validated(_ rawValue: String?) throws -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count == 4, sanitizedInput(trimmed) == trimmed else {
            throw ValidationError("银行卡后四位需填写 4 位数字")
        }
        return trimmed
    }

    static func maskedNumber(lastFour: String?) -> String {
        "•••• •••• •••• \(lastFour ?? "••••")"
    }
}
