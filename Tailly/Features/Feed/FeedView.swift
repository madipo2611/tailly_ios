import SwiftUI

struct FeedView: View {
    @Environment(\.graphQLClient) private var api
    @State private var posts: [Post] = []
    @State private var stories: [StoryFeedItem] = []
    @State private var error: String?
    @State private var isLoadingMore = false
    @State private var reachedEnd = false

    var body: some View {
        NavigationStack {
            TaillyScreen {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        StoryRail(items: stories)
                        ForEach(posts) { post in
                            PostCard(
                                post: post,
                                onLike: { await toggleLike(post) },
                                onCommentCreated: { incrementComments(for: post.id); await recordInteraction(postID: post.id, type: "comment") }
                            )
                            .onAppear {
                                if post.id == posts.last?.id { Task { await loadMore() } }
                            }
                        }
                        if isLoadingMore { ProgressView().frame(maxWidth: .infinity).padding() }
                    }
                    .padding(.vertical, 8)
                }
                .overlay { if posts.isEmpty && error == nil { ProgressView() } }
                .refreshable { await load(reset: true) }
            }
            .navigationTitle("tailly")
            .toolbar {
                if let error {
                    ToolbarItem(placement: .topBarTrailing) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityLabel(error)
                    }
                }
            }
        }
        .task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        do {
            if reset {
                async let postsRequest: PostsResponse = api.perform(GraphQLOperations.posts, variables: ["limit": .int(AppConfiguration.pageSize), "offset": .int(0)])
                async let storiesRequest: StoriesResponse = api.perform(GraphQLOperations.stories)
                let postResponse = try await postsRequest
                posts = postResponse.postsPaginated
                stories = try await storiesRequest.storyFeed.items
                reachedEnd = postResponse.postsPaginated.count < AppConfiguration.pageSize
            } else {
                let response: PostsResponse = try await api.perform(GraphQLOperations.posts, variables: ["limit": .int(AppConfiguration.pageSize), "offset": .int(posts.count)])
                posts += response.postsPaginated
                reachedEnd = response.postsPaginated.count < AppConfiguration.pageSize
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func loadMore() async {
        guard !isLoadingMore, !reachedEnd, !posts.isEmpty else { return }
        isLoadingMore = true; defer { isLoadingMore = false }
        do {
            let response: PostsResponse = try await api.perform(GraphQLOperations.posts, variables: ["limit": .int(AppConfiguration.pageSize), "offset": .int(posts.count)])
            let unseen = response.postsPaginated.filter { incoming in !posts.contains(where: { $0.id == incoming.id }) }
            posts += unseen
            reachedEnd = response.postsPaginated.count < AppConfiguration.pageSize
        } catch { self.error = error.localizedDescription }
    }

    private func toggleLike(_ post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let previous = posts[index]
        posts[index] = changing(previous, likes: max(0, previous.likesCount + (previous.isLiked ? -1 : 1)), liked: !previous.isLiked)
        do {
            let operation = previous.isLiked ? GraphQLOperations.unlikePost : GraphQLOperations.likePost
            let response: LikeResponse = try await api.perform(operation, variables: ["postId": .int(post.id)])
            if let current = posts.firstIndex(where: { $0.id == response.id }) { posts[current] = changing(posts[current], likes: response.likesCount, liked: response.isLiked) }
            if response.isLiked { await recordInteraction(postID: post.id, type: "like") }
        } catch {
            if let current = posts.firstIndex(where: { $0.id == previous.id }) { posts[current] = previous }
            self.error = error.localizedDescription
        }
    }

    private func incrementComments(for postID: Int) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let post = posts[index]
        posts[index] = Post(id: post.id, title: post.title, content: post.content, commentsCount: post.commentsCount + 1, likesCount: post.likesCount, isLiked: post.isLiked, createdAt: post.createdAt, author: post.author)
    }

    private func recordInteraction(postID: Int, type: String) async {
        let _: ExploreInteractionResponse? = try? await api.perform(GraphQLOperations.recordExploreInteraction, variables: ["contentId": .int(postID), "contentType": .string("post"), "interactionType": .string(type)])
    }

    private func changing(_ post: Post, likes: Int, liked: Bool) -> Post {
        Post(id: post.id, title: post.title, content: post.content, commentsCount: post.commentsCount, likesCount: likes, isLiked: liked, createdAt: post.createdAt, author: post.author)
    }
}

private struct PostsResponse: Decodable { let postsPaginated: [Post] }
private struct StoriesResponse: Decodable { let storyFeed: StoryFeed }
private struct LikeResponse: Decodable { let id: Int; let likesCount: Int; let isLiked: Bool }
private struct ExploreInteractionResponse: Decodable { let recordExploreInteraction: Bool }

private struct StoryRail: View {
    let items: [StoryFeedItem]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(items) { item in
                    VStack {
                        Circle().stroke(item.unseenCount > 0 ? TaillyTheme.accent : TaillyTheme.muted, lineWidth: 3).frame(width: 64, height: 64).overlay { Text(String(item.author.username.prefix(1)).uppercased()).font(.title2) }
                        Text(item.author.username).font(.caption).lineLimit(1)
                    }
                }
            }.padding(.horizontal)
        }
    }
}

private struct PostCard: View {
    let post: Post
    let onLike: () async -> Void
    let onCommentCreated: () async -> Void
    @State private var commentsVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Circle().fill(TaillyTheme.card).frame(width: 36, height: 36).overlay(Text(String(post.author.username.prefix(1)).uppercased())); Text(post.author.username).fontWeight(.semibold); Spacer() }
            AsyncImage(url: URL(string: post.content)) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(TaillyTheme.card).aspectRatio(1, contentMode: .fit).overlay(ProgressView()) }.clipShape(RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 16) {
                Button { Task { await onLike() } } label: { Label("\(post.likesCount)", systemImage: post.isLiked ? "heart.fill" : "heart") }.tint(post.isLiked ? .pink : .primary)
                Button { commentsVisible = true } label: { Label("\(post.commentsCount)", systemImage: "bubble.right") }
            }
            if !post.title.isEmpty { Text(post.title) }
        }
        .padding().background(TaillyTheme.surface, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal)
        .sheet(isPresented: $commentsVisible) { CommentsSheet(post: post, onCommentCreated: onCommentCreated) }
    }
}

private struct CommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.graphQLClient) private var api
    let post: Post
    let onCommentCreated: () async -> Void
    @State private var comments: [Comment] = []
    @State private var text = ""
    @State private var replyingTo: Comment?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(comments) { comment in
                    HStack(alignment: .top) {
                        Circle().fill(TaillyTheme.card).frame(width: 32, height: 32).overlay(Text(String(comment.author.username.prefix(1)).uppercased()))
                        VStack(alignment: .leading) {
                            Text(comment.author.username).fontWeight(.semibold)
                            Text(comment.content)
                            Button("Ответить") { replyingTo = comment }.font(.caption).foregroundStyle(TaillyTheme.accent)
                        }
                    }
                    .padding(.leading, comment.parentCommentId == nil ? 0 : 28)
                }
                .overlay { if comments.isEmpty && error == nil { ProgressView() } }
                if let replyingTo { HStack { Text("Ответ для @\(replyingTo.author.username)").font(.caption); Spacer(); Button { self.replyingTo = nil } label: { Image(systemName: "xmark.circle.fill") } }.padding(.horizontal) }
                if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
                HStack { TextField(replyingTo == nil ? "Комментарий" : "Ответ", text: $text, axis: .vertical).textFieldStyle(.roundedBorder); Button("Отправить") { Task { await send() } }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding()
            }
            .navigationTitle("Комментарии")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .task { await load() }
    }

    private func load() async { do { let response: CommentsResponse = try await api.perform(GraphQLOperations.postComments, variables: ["postId": .int(post.id)]); comments = response.comments; error = nil } catch { self.error = error.localizedDescription } }
    private func send() async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !content.isEmpty else { return }
        do {
            let parentID: JSONValue = replyingTo.map { .int($0.id) } ?? .null
            let response: CreateCommentResponse = try await api.perform(GraphQLOperations.createComment, variables: ["postId": .int(post.id), "content": .string(content), "parentCommentId": parentID])
            comments.append(response.createComment); text = ""; replyingTo = nil; error = nil; await onCommentCreated()
        } catch { self.error = error.localizedDescription }
    }
}
private struct CommentsResponse: Decodable { let comments: [Comment] }
private struct CreateCommentResponse: Decodable { let createComment: Comment }
