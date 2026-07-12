import Foundation
import Security

enum RecognitionRuntimeConfigurationError: LocalizedError {
    case missingEndpoint
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .missingEndpoint: "尚未配置识别服务"
        case .invalidEndpoint: "识别服务地址必须是 HTTPS 地址"
        }
    }
}

enum RecognitionRuntimeConfiguration {
    static let endpointDefaultsKey = "recognitionGatewayEndpoint"
    static let keychainService = "com.ian.MultiCurrencyLedger.recognition"
    static let keychainAccount = "gatewayBearerToken"

    static func makeHTTPClient() throws -> RecognitionHTTPClient {
        guard let endpointString = UserDefaults.standard.string(forKey: endpointDefaultsKey),
              let endpoint = URL(string: endpointString) else {
            throw RecognitionRuntimeConfigurationError.missingEndpoint
        }
        return try RecognitionHTTPClient(endpoint: endpoint, bearerToken: bearerToken)
    }

    static func save(endpointString: String, bearerToken: String) throws {
        let cleanEndpoint = endpointString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: cleanEndpoint), endpoint.scheme?.lowercased() == "https" else {
            throw RecognitionRuntimeConfigurationError.invalidEndpoint
        }
        _ = try RecognitionHTTPClient(endpoint: endpoint)
        UserDefaults.standard.set(cleanEndpoint, forKey: endpointDefaultsKey)
        try saveBearerToken(bearerToken)
    }

    static func clear() throws {
        UserDefaults.standard.removeObject(forKey: endpointDefaultsKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func bearerToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveBearerToken(_ token: String) throws {
        let data = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
