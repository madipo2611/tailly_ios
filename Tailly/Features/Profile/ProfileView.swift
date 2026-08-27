import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.graphQLClient) private var api
    @State private var me: Me?
    @State private var error: String?
    @State private var isEditing = false
    @State private var isChangingPassword = false

    var body: some View {
        NavigationStack {
            TaillyScreen {
                Group {
                    if let me {
                        VStack(spacing: 18) {
                            avatar(for: me)
                            Text(me.username).font(.title.bold())
                            Text(me.email).foregroundStyle(TaillyTheme.muted)
                            HStack(spacing: 36) {
                                Stat(value: me.followersCount, label: "подписчиков")
                                Stat(value: me.followingCount, label: "подписок")
                            }
                            Divider()
                            Button("Редактировать профиль") { isEditing = true }
                                .buttonStyle(.borderedProminent)
                            Button("Изменить пароль") { isChangingPassword = true }
                                .buttonStyle(.bordered)
                            ContentUnavailableView(
                                "Публикации",
                                systemImage: "square.grid.2x2",
                                description: Text("Посты профиля будут подключены следующим шагом.")
                            )
                            Button("Выйти", role: .destructive) { session.signOut() }
                                .buttonStyle(.bordered)
                        }
                        .padding()
                    } else if let error {
                        ContentUnavailableView("Не удалось загрузить профиль", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(error))
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Профиль")
        }
        .task { await load() }
        .sheet(isPresented: $isEditing) {
            if let me {
                EditProfileSheet(me: me) { updated in
                    self.me = updated
                    isEditing = false
                }
            }
        }
        .sheet(isPresented: $isChangingPassword) { ChangePasswordSheet() }
    }

    @ViewBuilder
    private func avatar(for me: Me) -> some View {
        if let url = URL(string: me.avatar), !me.avatar.isEmpty {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                avatarPlaceholder(for: me)
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
        } else {
            avatarPlaceholder(for: me)
        }
    }

    private func avatarPlaceholder(for me: Me) -> some View {
        Circle().fill(TaillyTheme.card).frame(width: 96, height: 96)
            .overlay(Text(String(me.username.prefix(1)).uppercased()).font(.largeTitle))
    }

    private func load() async {
        do {
            let response: MeResponse = try await api.perform(GraphQLOperations.me)
            me = response.me
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.graphQLClient) private var api
    let me: Me
    let onSaved: (Me) -> Void
    @State private var username: String
    @State private var email: String
    @State private var avatar: String
    @State private var error: String?
    @State private var isSaving = false

    init(me: Me, onSaved: @escaping (Me) -> Void) {
        self.me = me
        self.onSaved = onSaved
        _username = State(initialValue: me.username)
        _email = State(initialValue: me.email)
        _avatar = State(initialValue: me.avatar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Профиль") {
                    TextField("Имя пользователя", text: $username)
                        .textInputAutocapitalization(.never)
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TextField("Ссылка на аватар", text: $avatar)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Редактировать")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Сохранение…" : "Сохранить") { Task { await save() } }
                        .disabled(isSaving || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let response: UpdateProfileResponse = try await api.perform(GraphQLOperations.updateProfile, variables: [
                "username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)),
                "email": .string(email.trimmingCharacters(in: .whitespacesAndNewlines)),
                "avatar": .string(avatar.trimmingCharacters(in: .whitespacesAndNewlines))
            ])
            onSaved(Me(user: response.updateProfile))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.graphQLClient) private var api
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Новый пароль") {
                    SecureField("Текущий пароль", text: $oldPassword)
                    SecureField("Новый пароль", text: $newPassword)
                    SecureField("Повторите новый пароль", text: $confirmation)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Сменить пароль")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Сохранение…" : "Сохранить") { Task { await save() } }
                        .disabled(isSaving || oldPassword.isEmpty || newPassword.isEmpty || confirmation.isEmpty)
                }
            }
        }
    }

    private func save() async {
        guard newPassword == confirmation else {
            error = "Новые пароли не совпадают."
            return
        }
        guard newPassword.count >= 8 else {
            error = "Пароль должен содержать не менее 8 символов."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let response: ChangePasswordResponse = try await api.perform(GraphQLOperations.changePassword, variables: [
                "oldPassword": .string(oldPassword), "newPassword": .string(newPassword)
            ])
            guard response.changePassword else {
                error = "Не удалось изменить пароль."
                return
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct MeResponse: Decodable { let me: Me }
private struct UpdateProfileResponse: Decodable { let updateProfile: UpdatedProfile }
private struct UpdatedProfile: Decodable {
    let id: Int
    let email: String
    let username: String
    let avatar: String
    let followersCount: Int
    let followingCount: Int
}
private struct ChangePasswordResponse: Decodable { let changePassword: Bool }

private extension Me {
    init(user: UpdatedProfile) {
        self.init(id: user.id, email: user.email, username: user.username, avatar: user.avatar, followersCount: user.followersCount, followingCount: user.followingCount)
    }
}

private struct Stat: View {
    let value: Int
    let label: String
    var body: some View {
        VStack {
            Text("\(value)").font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(TaillyTheme.muted)
        }
    }
}
