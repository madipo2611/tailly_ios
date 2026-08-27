import Foundation

/// graphql-transport-ws client. The server must be verified against this protocol before enabling it in UI.
actor GraphQLSubscriptionClient {
    private var socket: URLSessionWebSocketTask?

    func connect(accessToken: String) {
        var components = URLComponents(url: AppConfiguration.webSocketEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: accessToken)]
        socket = URLSession.shared.webSocketTask(with: components.url!)
        socket?.resume()
    }

    func disconnect() { socket?.cancel(with: .goingAway, reason: nil); socket = nil }
}
