import XCTest
@testable import MultiCurrencyLedger

final class RecognitionHTTPClientTests: XCTestCase {
    func testSendsMinimalJSONRequestAndReturnsSuccessfulBody() async throws {
        let expected = Data(#"{"results":[]}"#.utf8)
        let transport = RecognitionHTTPTransportStub { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/recognize")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = try XCTUnwrap(request.httpBody)
            let decoded = try JSONDecoder().decode(RecognitionAPIRequest.self, from: body)
            XCTAssertEqual(decoded.ocrText, "CNY 28.00")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, expected)
        }

        let client = try RecognitionHTTPClient(
            endpoint: URL(string: "https://example.test/recognize")!,
            bearerToken: { "test-token" },
            session: transport
        )
        let result = try await client.recognize(makeRequest())

        XCTAssertEqual(result, expected)
    }

    func testRejectsInsecureEndpointAndNonSuccessStatus() async throws {
        XCTAssertThrowsError(try RecognitionHTTPClient(endpoint: URL(string: "http://example.test")!)) {
            XCTAssertEqual($0 as? RecognitionHTTPClientError, .insecureEndpoint)
        }

        let transport = RecognitionHTTPTransportStub { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = try RecognitionHTTPClient(
            endpoint: URL(string: "https://example.test")!,
            session: transport
        )
        do {
            _ = try await client.recognize(makeRequest())
            XCTFail("Expected HTTP status failure")
        } catch {
            XCTAssertEqual(error as? RecognitionHTTPClientError, .httpStatus(401))
        }
    }

    private func makeRequest() -> RecognitionAPIRequest {
        let localContext = RecognitionRequestContext(
            bookID: UUID(), bookName: "日常账本", accounts: [], categories: []
        )
        return RecognitionAPIRequest(
            ocrText: "CNY 28.00",
            context: RecognitionRemoteContext(localContext: localContext),
            requestedAt: Date(timeIntervalSince1970: 0)
        )
    }

}

private final class RecognitionHTTPTransportStub: RecognitionHTTPTransport {
    let handler: (URLRequest) throws -> (HTTPURLResponse, Data)

    init(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (response, data) = try handler(request)
        return (data, response)
    }
}
