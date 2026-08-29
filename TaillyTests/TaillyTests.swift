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

    func testOfflineErrorHasActionableRussianMessage() async {
        URLProtocolStub.handler = { _ in throw URLError(.notConnectedToInternet) }

        struct Response: Decodable { let value: Int }
        do {
            let _: Response = try await makeClient().perform("query Value { value }")
            XCTFail("Expected an offline error")
        } catch let error as GraphQLError {
            XCTAssertEqual(error.errorDescription, "Нет подключения к интернету. Проверьте сеть и повторите попытку.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUploadUsesGraphQLMultipartRequestFormat() async throws {
        URLProtocolStub.handler = { request in
            let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
            XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary=TaillyBoundary-"))
            return .json("{\"data\":{\"uploaded\":true}}")
        }

        struct Response: Decodable { let uploaded: Bool }
        let response: Response = try await makeClient().performUpload(
            "mutation Upload($content: Upload!) { upload(content: $content) { uploaded } }",
            variables: ["content": .string("placeholder")],
            upload: GraphQLUpload(data: Data("image-data".utf8), filename: "photo.jpg", mimeType: "image/jpeg"),
            variableName: "content"
        )

        XCTAssertTrue(response.uploaded)
    }

    func testUnauthenticatedResponseRefreshesAndRetriesOnce() async throws {
        let session = SessionStore()
        defer { session.signOut() }
        session.save(accessToken: jwt(expiringIn: 3600), refreshToken: "refresh-token")
        var applicationRequestCount = 0
        var refreshRequestCount = 0
        URLProtocolStub.handler = { request in
            if request.value(forHTTPHeaderField: "bypass-auth") == "true" {
                refreshRequestCount += 1
                return .json("{\"data\":{\"refreshTokens\":{\"accessToken\":\"new-access\",\"refreshToken\":\"new-refresh\"}}}")
            }
            applicationRequestCount += 1
            if applicationRequestCount == 1 {
                let authorization = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertTrue(authorization.hasPrefix("Bearer "))
                XCTAssertGreaterThan(authorization.count, "Bearer ".count)
                return .json("{\"errors\":[{\"message\":\"expired\",\"extensions\":{\"code\":\"UNAUTHENTICATED\"}}]}")
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
            return .json("{\"data\":{\"value\":7}}")
        }

        struct Response: Decodable { let value: Int }
        let response: Response = try await makeClient(session: session).perform("query Value { value }")

        XCTAssertEqual(response.value, 7)
        XCTAssertEqual(applicationRequestCount, 2)
        XCTAssertEqual(refreshRequestCount, 1)
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
