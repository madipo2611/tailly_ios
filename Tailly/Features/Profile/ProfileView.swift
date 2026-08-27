import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore; @Environment(\.graphQLClient) private var api
    @State private var me: Me?; @State private var error: String?
    var body: some View { NavigationStack { TaillyScreen { Group { if let me { VStack(spacing: 18) { Circle().fill(TaillyTheme.card).frame(width: 96, height: 96).overlay(Text(String(me.username.prefix(1)).uppercased()).font(.largeTitle)); Text(me.username).font(.title.bold()); Text(me.email).foregroundStyle(TaillyTheme.muted); HStack(spacing: 36) { Stat(value: me.followersCount, label: "подписчиков"); Stat(value: me.followingCount, label: "подписок") }; Divider(); ContentUnavailableView("Публикации", systemImage: "square.grid.2x2", description: Text("Посты профиля и редактирование будут подключены следующим шагом.")); Button("Выйти", role: .destructive) { session.signOut() }.buttonStyle(.bordered) }.padding() } else if let error { ContentUnavailableView("Не удалось загрузить профиль", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(error)) } else { ProgressView() } } }.navigationTitle("Профиль") }.task { await load() } }
    private func load() async { do { struct Response: Decodable { let me: Me }; let response: Response = try await api.perform(GraphQLOperations.me); me = response.me } catch { self.error = error.localizedDescription } }
}
private struct Stat: View { let value: Int; let label: String; var body: some View { VStack { Text("\(value)").font(.title3.bold()); Text(label).font(.caption).foregroundStyle(TaillyTheme.muted) } } }
