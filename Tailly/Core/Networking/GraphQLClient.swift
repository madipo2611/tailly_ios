import Foundation
import SwiftUI

struct GraphQLError: LocalizedError { let message: String; var errorDescription: String? { message } }

struct GraphQLUpload {
    let data: Data
    let filename: String
    let mimeType: String
}

private struct GraphQLRequest: Encodable { let query: String; let variables: [String: JSONValue]? }
private struct GraphQLResponse<Result: Decodable>: Decodable { let data: Result?; let errors: [GraphQLErrorPayload]? }
private struct GraphQLErrorPayload: Decodable {
    let message: String
    let extensions: Extensions?
    struct Extensions: Decodable { let code: String? }
    var isUnauthenticated: Bool { extensions?.code?.uppercased() == "UNAUTHENTICATED" || message.uppercased().contains("UNAUTHENTICATED") }
}

private actor RefreshCoordinator {
    private var task: Task<Void, Error>?
    func refresh(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        if let task { return try await task.value }
        let task = Task { try await operation() }
        self.task = task
        defer { self.task = nil }
        try await task.value
    }
}

final class GraphQLClient: @unchecked Sendable {
    private let session: SessionStore
    private let urlSession: URLSession
    private let endpoint: URL
    private let refreshCoordinator = RefreshCoordinator()

    init(session: SessionStore, urlSession: URLSession = .shared, endpoint: URL = AppConfiguration.graphQLEndpoint) {
        self.session = session; self.urlSession = urlSession; self.endpoint = endpoint
    }

    func perform<Result: Decodable>(_ operation: String, variables: [String: JSONValue]? = nil) async throws -> Result {
        try await refreshAccessTokenIfNeeded()
        return try await perform(operation, variables: variables, upload: nil, retryingAfterRefresh: true)
    }

    /// Sends a request compliant with the GraphQL multipart request specification.
    /// `variableName` is a top-level variable such as `content` or `video`.
    func performUpload<Result: Decodable>(_ operation: String, variables: [String: JSONValue], upload: GraphQLUpload, variableName: String) async throws -> Result {
        try await refreshAccessTokenIfNeeded()
        var variables = variables
        variables[variableName] = .null
        return try await perform(operation, variables: variables, upload: (upload, variableName), retryingAfterRefresh: true)
    }

    private func perform<Result: Decodable>(_ operation: String, variables: [String: JSONValue]?, upload: (GraphQLUpload, String)?, retryingAfterRefresh: Bool) async throws -> Result {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if let token = session.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let upload {
            let boundary = "TaillyBoundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = try multipartBody(operation: operation, variables: variables, upload: upload.0, variablePath: upload.1, boundary: boundary)
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: operation, variables: variables))
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw userFacingNetworkError(for: error)
        }
        guard let http = response as? HTTPURLResponse else { throw GraphQLError(message: "Некорректный ответ сервера") }
        if http.statusCode == 401, retryingAfterRefresh {
            try await refreshAccessToken(force: true, failingAccessToken: request.value(forHTTPHeaderField: "Authorization"))
            return try await perform(operation, variables: variables, upload: upload, retryingAfterRefresh: false)
        }
        guard http.statusCode == 200 else { throw GraphQLError(message: serverErrorMessage(for: http.statusCode)) }
        let payload = try JSONDecoder().decode(GraphQLResponse<Result>.self, from: data)
        if let error = payload.errors?.first {
            if error.isUnauthenticated, retryingAfterRefresh {
                try await refreshAccessToken(force: true, failingAccessToken: request.value(forHTTPHeaderField: "Authorization"))
                return try await perform(operation, variables: variables, upload: upload, retryingAfterRefresh: false)
            }
            throw GraphQLError(message: error.message)
        }
        guard let result = payload.data else { throw GraphQLError(message: "GraphQL returned no data") }
        return result
    }

    private func refreshAccessTokenIfNeeded() async throws {
        guard let accessToken = session.accessToken, jwtExpiresSoon(accessToken) else { return }
        try await refreshAccessToken(force: false, failingAccessToken: nil)
    }

    private func refreshAccessToken(force: Bool, failingAccessToken: String?) async throws {
        guard let refreshToken = session.refreshToken else { throw GraphQLError(message: "Сессия истекла") }
        try await refreshCoordinator.refresh { [weak self] in
            guard let self else { return }
            if force, let failingAccessToken, self.session.accessToken.map({ "Bearer \($0)" }) != failingAccessToken { return }
            if !force, let token = self.session.accessToken, !self.jwtExpiresSoon(token) { return }
            try await self.requestTokenRefresh(refreshToken: refreshToken)
        }
    }

    private func requestTokenRefresh(refreshToken: String) async throws {
        struct RefreshResponse: Decodable { let refreshTokens: Tokens }
        struct Tokens: Decodable { let accessToken: String; let refreshToken: String }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("true", forHTTPHeaderField: "bypass-auth")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: "mutation Refresh($refreshToken: String!) { refreshTokens(refreshToken: $refreshToken) { accessToken refreshToken } }", variables: ["refreshToken": .string(refreshToken)]))
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw userFacingNetworkError(for: error)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw GraphQLError(message: "Не удалось обновить сессию") }
        let payload = try JSONDecoder().decode(GraphQLResponse<RefreshResponse>.self, from: data)
        if let error = payload.errors?.first { throw GraphQLError(message: error.message) }
        guard let tokens = payload.data?.refreshTokens else { throw GraphQLError(message: "Сессия истекла") }
        session.save(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
    }

    private func multipartBody(operation: String, variables: [String: JSONValue]?, upload: GraphQLUpload, variablePath: String, boundary: String) throws -> Data {
        let operations = try JSONEncoder().encode(GraphQLRequest(query: operation, variables: variables))
        let map = try JSONEncoder().encode(["0": ["variables.\(variablePath)"]])
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        func field(_ name: String, _ value: Data) { append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\nContent-Type: application/json\r\n\r\n"); body.append(value); append("\r\n") }
        field("operations", operations); field("map", map)
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"0\"; filename=\"\(upload.filename)\"\r\nContent-Type: \(upload.mimeType)\r\n\r\n")
        body.append(upload.data); append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func jwtExpiresSoon(_ token: String, leeway: TimeInterval = 60) -> Bool {
        guard let part = token.split(separator: ".").dropFirst().first,
              let data = Data(base64Encoded: String(part).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/").padding(toLength: ((part.count + 3) / 4) * 4, withPad: "=", startingAt: 0)),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let expiration = payload["exp"] as? TimeInterval else { return true }
        return Date().timeIntervalSince1970 + leeway >= expiration
    }

    private func userFacingNetworkError(for error: Error) -> GraphQLError {
        guard let urlError = error as? URLError else { return GraphQLError(message: "Не удалось выполнить запрос. Повторите попытку.") }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return GraphQLError(message: "Нет подключения к интернету. Проверьте сеть и повторите попытку.")
        case .timedOut:
            return GraphQLError(message: "Сервер не ответил вовремя. Повторите попытку.")
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return GraphQLError(message: "Сервер временно недоступен. Повторите попытку позже.")
        default:
            return GraphQLError(message: "Не удалось выполнить запрос. Повторите попытку.")
        }
    }

    private func serverErrorMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 500...599: return "Сервер временно недоступен. Повторите попытку позже."
        default: return "Не удалось выполнить запрос. Повторите попытку."
        }
    }
}

private struct GraphQLClientKey: EnvironmentKey { static let defaultValue = GraphQLClient(session: SessionStore()) }
extension EnvironmentValues { var graphQLClient: GraphQLClient { get { self[GraphQLClientKey.self] } set { self[GraphQLClientKey.self] = newValue } } }
