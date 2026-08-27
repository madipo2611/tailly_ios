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
    @State private var selection: PhotosPickerItem?; @State private var videoSelection: PhotosPickerItem?; @State private var title = ""; @State private var imageData: Data?; @State private var videoData: Data?; @State private var isUploading = false; @State private var error: String?; @State private var published = false
    var body: some View { NavigationStack { TaillyScreen { Form { Section("Новый пост") { PhotosPicker(selection: $selection, matching: .images) { Label(imageData == nil ? "Выбрать фото" : "Фото выбрано", systemImage: "photo") }.onChange(of: selection) { _, item in Task { imageData = try? await item?.loadTransferable(type: Data.self) } }; TextField("Подпись", text: $title); Button { Task { await publish() } } label: { if isUploading && imageData != nil { ProgressView() } else { Text("Опубликовать пост") } }.disabled(imageData == nil || isUploading) }; Section("Новый клип") { PhotosPicker(selection: $videoSelection, matching: .videos) { Label(videoData == nil ? "Выбрать видео" : "Видео выбрано", systemImage: "video") }.onChange(of: videoSelection) { _, item in Task { await loadVideo(from: item) } }; Text("Максимальный размер видео — 100 МБ.").font(.caption).foregroundStyle(TaillyTheme.muted); Button { Task { await publishClip() } } label: { if isUploading && videoData != nil { ProgressView() } else { Text("Опубликовать клип") } }.disabled(videoData == nil || isUploading) }; if let error { Section { Text(error).foregroundStyle(.red) } }; if published { Section { Text("Контент опубликован").foregroundStyle(.green) } } }.scrollContentBackground(.hidden) }.navigationTitle("Создать") } }
    private func publish() async { guard let imageData else { return }; isUploading = true; defer { isUploading = false }; do { let jpegData = UIImage(data: imageData)?.jpegData(compressionQuality: 0.9) ?? imageData; let upload = GraphQLUpload(data: jpegData, filename: "post-\(UUID().uuidString).jpg", mimeType: "image/jpeg"); let _: CreatePostResponse = try await api.performUpload(GraphQLOperations.createPost, variables: ["title": .string(title)], upload: upload, variableName: "content"); title = ""; selection = nil; self.imageData = nil; published = true; error = nil } catch { self.error = error.localizedDescription } }
    private func loadVideo(from item: PhotosPickerItem?) async { guard let item else { videoData = nil; return }; do { let data = try await item.loadTransferable(type: Data.self); guard let data else { throw GraphQLError(message: "Не удалось прочитать выбранное видео.") }; guard data.count <= 100 * 1_024 * 1_024 else { throw GraphQLError(message: "Видео больше 100 МБ. Выберите файл меньшего размера.") }; videoData = data; error = nil } catch { videoData = nil; self.error = error.localizedDescription } }
    private func publishClip() async { guard let videoData else { return }; isUploading = true; defer { isUploading = false }; do { let upload = GraphQLUpload(data: videoData, filename: "clip-\(UUID().uuidString).mp4", mimeType: "video/mp4"); let _: CreateClipResponse = try await api.performUpload(GraphQLOperations.createClip, variables: ["title": title.isEmpty ? .null : .string(title)], upload: upload, variableName: "video"); title = ""; videoSelection = nil; self.videoData = nil; published = true; error = nil } catch { self.error = error.localizedDescription } }
}
private struct CreatePostResponse: Decodable { let createPost: Post }
private struct CreateClipResponse: Decodable { let createClip: Clip }
