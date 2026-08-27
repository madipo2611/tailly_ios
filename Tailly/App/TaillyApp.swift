import SwiftUI

@main
struct TaillyApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environment(\.graphQLClient, GraphQLClient(session: session))
                .preferredColorScheme(.dark)
        }
    }
}
