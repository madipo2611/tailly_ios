import Foundation

enum AppConfiguration {
    static let graphQLEndpoint = URL(string: "https://tailly.ru/query")!
    static let webSocketEndpoint = URL(string: "wss://tailly.ru/ws")!
    static let pageSize = 20
}
