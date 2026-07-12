import Foundation

enum RecognitionHTTPClientError: LocalizedError, Equatable {
    case insecureEndpoint
    case missingResponse
    case httpStatus(Int)
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .insecureEndpoint: "识别服务必须使用 HTTPS"
        case .missingResponse: "识别服务未返回有效响应"
        case let .httpStatus(code): "识别服务返回 HTTP \(code)"
        case .responseTooLarge: "识别服务返回内容过大"
        }
    }
}

protocol RecognitionHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: RecognitionHTTPTransport {}

final class RecognitionHTTPClient: RecognitionAPIClient {
    typealias BearerTokenProvider = () throws -> String?

    private let endpoint: URL
    private let bearerToken: BearerTokenProvider
    private let transport: RecognitionHTTPTransport
    private let maximumResponseBytes: Int

    init(
        endpoint: URL,
        bearerToken: @escaping BearerTokenProvider = { nil },
        session: RecognitionHTTPTransport = URLSession.shared,
        maximumResponseBytes: Int = 1_000_000
    ) throws {
        guard endpoint.scheme?.lowercased() == "https" else {
            throw RecognitionHTTPClientError.insecureEndpoint
        }
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        transport = session
        self.maximumResponseBytes = maximumResponseBytes
    }

    func recognize(_ request: RecognitionAPIRequest) async throws -> Data {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try bearerToken()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await transport.data(for: urlRequest)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecognitionHTTPClientError.missingResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RecognitionHTTPClientError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= maximumResponseBytes else {
            throw RecognitionHTTPClientError.responseTooLarge
        }
        return data
    }
}
