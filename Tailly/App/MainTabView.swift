import PhotosUI
import SwiftUI
import UIKit

struct MainTabView: View {
    var body: some View {
        TabView {
            FeedView().tabItem { Label("Лента", systemImage: "house") }
            ExploreView().tabItem { Label("Интересное", systemImage: "safari") }
            ClipsView().tabItem { Label("Клипы", systemImage: "play.rectangle") }
            CreatePlaceholderView().tabItem { Label("Создать", systemImage: "plus.square") }
            MessagesView().tabItem { Label("Сообщения", systemImage: "paperplane") }
            ProfileView().tabItem { Label("Профиль", systemImage: "person") }
        }
        .tint(TaillyTheme.accent)
    }
}

struct CreatePlaceholderView: View {
    @Environment(\.graphQLClient) private var api
    @State private var selection: PhotosPickerItem?; @State private var title = ""; @State private var imageData: Data?; @State private var isUploading = false; @State private var error: String?; @State private var published = false
    var body: some View { NavigationStack { TaillyScreen { Form { Section("Новый пост") { PhotosPicker(selection: $selection, matching: .images) { Label(imageData == nil ? "Выбрать фото" : "Фото выбрано", systemImage: "photo") }.onChange(of: selection) { _, item in Task { imageData = try? await item?.loadTransferable(type: Data.self) } }; TextField("Подпись", text: $title); if let error { Text(error).foregroundStyle(.red) }; if published { Text("Пост опубликован").foregroundStyle(.green) } }; Section { Button { Task { await publish() } } label: { if isUploading { ProgressView() } else { Text("Опубликовать") } }.disabled(imageData == nil || isUploading) } }.scrollContentBackground(.hidden) }.navigationTitle("Создать") } }
    private func publish() async { guard let imageData else { return }; isUploading = true; defer { isUploading = false }; do { let jpegData = UIImage(data: imageData)?.jpegData(compressionQuality: 0.9) ?? imageData; let upload = GraphQLUpload(data: jpegData, filename: "post-\(UUID().uuidString).jpg", mimeType: "image/jpeg"); let _: CreatePostResponse = try await api.performUpload(GraphQLOperations.createPost, variables: ["title": .string(title)], upload: upload, variableName: "content"); title = ""; selection = nil; self.imageData = nil; published = true; error = nil } catch { self.error = error.localizedDescription } }
}
private struct CreatePostResponse: Decodable { let createPost: Post }
