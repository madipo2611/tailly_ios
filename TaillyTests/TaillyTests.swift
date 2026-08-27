import XCTest
@testable import Tailly

final class TaillyTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testJSONValueEncodes() throws {
        XCTAssertEqual(String(data: try JSONEncoder().encode(JSONValue.object(["id": .int(42)])), encoding: .utf8), "{\"id\":42}")
    }

    func testPerformDecodesGraphQLResponse() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return .json("{\"data\":{\"value\":42}}")
        }

        struct Response: Decodable { let value: Int }
        let client = makeClient()
        let response: Response = try await client.perform("query Value { value }")

        XCTAssertEqual(response.value, 42)
    }

    func testUnauthenticatedResponseRefreshesAndRetriesOnce() async throws {
        let session = SessionStore()
        defer { session.signOut() }
        session.save(accessToken: jwt(expiringIn: 3600), refreshToken: "refresh-token")
        var requestCount = 0
        URLProtocolStub.handler = { request in
            requestCount += 1
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            if body.contains("mutation Refresh") {
                return .json("{\"data\":{\"refreshTokens\":{\"accessToken\":\"new-access\",\"refreshToken\":\"new-refresh\"}}}")
            }
            if requestCount == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(session.accessToken ?? \"\")")
                return .json("{\"errors\":[{\"message\":\"expired\",\"extensions\":{\"code\":\"UNAUTHENTICATED\"}}]}")
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
            return .json("{\"data\":{\"value\":7}}")
        }

        struct Response: Decodable { let value: Int }
        let response: Response = try await makeClient(session: session).perform("query Value { value }")

        XCTAssertEqual(response.value, 7)
        XCTAssertEqual(requestCount, 3)
    }

    private func makeClient(session: SessionStore = SessionStore()) -> GraphQLClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return GraphQLClient(session: session, urlSession: URLSession(configuration: configuration), endpoint: URL(string: "https://example.test/query")!)
    }

    private func jwt(expiringIn seconds: TimeInterval) -> String {
        let header = Data("{\"alg\":\"none\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let payload = Data("{\"exp\":\(Int(Date().timeIntervalSince1970 + seconds))}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "\(header).\(payload).signature"
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> StubResponse)?

    static func reset() { handler = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let response = try Self.handler?(request) else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct StubResponse {
    let statusCode: Int
    let data: Data

    static func json(_ string: String, statusCode: Int = 200) -> Self {
        Self(statusCode: statusCode, data: Data(string.utf8))
    }
}
