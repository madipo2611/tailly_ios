import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isRestoring { ProgressView() }
            else if session.isAuthenticated { MainTabView() }
            else { AuthenticationView() }
        }
        .tint(TaillyTheme.accent)
        .task { await session.restore() }
    }
}
