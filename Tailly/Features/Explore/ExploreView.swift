import SwiftUI

private enum ExploreFilter: String, CaseIterable, Identifiable {
    case all, post, clip
    var id: Self { self }
    var title: String { switch self { case .all: return "Всё"; case .post: return "Фото"; case .clip: return "Клипы" } }
    var apiValue: JSONValue { self == .all ? .null : .string(rawValue) }
}

struct ExploreView: View {
    @Environment(\.graphQLClient) private var api
    @State private var filter: ExploreFilter = .all
    @State private var items: [ExploreItem] = []
    @State private var isLoading = false; @State private var canLoadMore = true; @State private var error: String?

    var body: some View {
        NavigationStack {
            TaillyScreen {
                ScrollView {
                    Picker("Тип рекомендаций", selection: $filter) { ForEach(ExploreFilter.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).padding()
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                        ForEach(items) { item in ExploreCard(item: item).onTapGesture { Task { await recordView(of: item) } } }
                    }
                    if canLoadMore { ProgressView().padding().onAppear { Task { await loadMore() } } }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red).padding() }
                }.refreshable { await reload() }
            }.navigationTitle("Интересное")
        }.task { await reload() }.onChange(of: filter) { _, _ in Task { await reload() } }
    }

    private func reload() async { items = []; canLoadMore = true; error = nil; await loadMore() }
    private func loadMore() async {
        guard !isLoading && canLoadMore else { return }; isLoading = true; defer { isLoading = false }
        do {
            let result: ExploreResponse = try await api.perform(GraphQLOperations.explore, variables: ["limit": .int(12), "offset": .int(items.count), "contentType": filter.apiValue])
            let existing = Set(items.map(\.id)); let newItems = result.exploreFeed.filter { !existing.contains($0.id) }
            items += newItems; canLoadMore = result.exploreFeed.count == 12; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func recordView(of item: ExploreItem) async {
        struct Response: Decodable { let recordExploreInteraction: Bool }
        _ = try? await api.perform(GraphQLOperations.recordExploreInteraction, variables: ["contentId": .int(item.contentId), "contentType": .string(item.contentType), "interactionType": .string("view")]) as Response
    }
}

private struct ExploreResponse: Decodable { let exploreFeed: [ExploreItem] }
private struct ExploreCard: View {
    let item: ExploreItem
    var body: some View { ZStack(alignment: .bottomLeading) {
        AsyncImage(url: URL(string: item.thumbnailUrl ?? item.mediaUrl)) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(TaillyTheme.card) }
        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
        HStack { if item.contentType == "clip" { Image(systemName: "play.fill") }; Spacer(); Label("\(item.likesCount)", systemImage: "heart.fill") }.font(.caption.bold()).padding(8)
    }.frame(height: 220).clipped() }
}
