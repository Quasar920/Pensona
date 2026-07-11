import Foundation

/// Optional remote-rate capability. The MVP uses manual rates, so no provider URL is hard-coded.
struct ExchangeRateRemoteClient {
    struct Response: Decodable {
        let base: String
        let rates: [String: Decimal]
    }

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(from endpoint: URL) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RemoteRateError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

enum RemoteRateError: LocalizedError {
    case invalidResponse
    var errorDescription: String? { "远程汇率服务返回了无效响应" }
}
