import Foundation

struct User: Identifiable, Decodable, Hashable { let id: Int; let username: String; let avatar: String }
struct Me: Decodable, Hashable { let id: Int; let email: String; let username: String; let avatar: String; let followersCount: Int; let followingCount: Int }
struct Post: Identifiable, Decodable, Hashable { let id: Int; let title: String; let content: String; let commentsCount: Int; let likesCount: Int; let isLiked: Bool; let createdAt: String; let author: User }
struct Comment: Identifiable, Decodable, Hashable { let id: Int; let content: String; let author: User; let parentCommentId: Int?; let createdAt: String }
struct Clip: Identifiable, Decodable, Hashable { let id: Int; let title: String?; let videoUrl: String; let thumbnailUrl: String?; let commentsCount: Int; let likesCount: Int; let isLiked: Bool; let createdAt: String; let author: User }
struct ClipComment: Identifiable, Decodable, Hashable { let id: Int; let clipId: Int; let content: String; let author: User; let parentCommentId: Int?; let createdAt: String; let updatedAt: String }
struct Message: Identifiable, Decodable, Hashable { let id: Int; let chatId: Int; let senderId: Int; let receiverId: Int; let content: String; let status: String; let createdAt: String }
struct Chat: Identifiable, Decodable, Hashable { let id: Int; let user1Id: Int; let user2Id: Int; let updatedAt: String; let unreadCount: Int; let lastMessage: Message? }

struct StoryFeed: Decodable { let items: [StoryFeedItem]; let nextPageToken: String? }
struct StoryFeedItem: Identifiable, Decodable { var id: Int { author.id }; let author: User; let stories: [Story]; let unseenCount: Int }
struct Story: Identifiable, Decodable { let id: Int; let caption: String; let mediaType: String; let sourceUrl: String; let previewUrl: String?; let createdAt: String; let author: User }
struct ExploreItem: Identifiable, Decodable, Hashable {
    var id: String { "\(contentType)-\(contentId)" }
    let contentType: String; let contentId: Int; let relevanceScore: Double
    let title: String; let mediaUrl: String; let thumbnailUrl: String?
    let author: User?; let likesCount: Int; let commentsCount: Int; let isLiked: Bool; let createdAt: String
}
