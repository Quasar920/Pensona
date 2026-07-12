import Foundation
import Security

enum RecognitionRuntimeConfigurationError: LocalizedError {
    case missingEndpoint

    var errorDescription: String? { "尚未配置识别服务" }
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
}
