import Foundation

enum CommunityFeedScope: String, CaseIterable, Identifiable {
    case publicFeed
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicFeed: return "广场"
        case .following: return "关注"
        }
    }
}

enum CommunityFeedSort: Int, CaseIterable, Identifiable {
    case latest = 1
    case hottest = 2
    case discussed = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .latest: return "最新"
        case .hottest: return "最热"
        case .discussed: return "热议"
        }
    }
}

struct CommunityTopic: Identifiable, Hashable {
    let id: String
    let name: String

    init(id: String? = nil, name: String) {
        self.id = id ?? "custom:\(name)"
        self.name = name
    }

    var platformObject: JSONObject {
        if id.hasPrefix("custom:") {
            return ["name": name]
        }
        return ["id": id, "name": name]
    }
}

struct CommunityVideo: Hashable {
    let path: String
    let coverURL: URL?
    let title: String?
    let width: Int?
    let height: Int?
    let isLocked: Bool
}

struct CommunityPost: Identifiable, Hashable {
    let id: String
    let authorID: String?
    let author: String
    let avatarURL: URL?
    let content: String
    let createdAt: String?
    let imageURLs: [URL]
    let video: CommunityVideo?
    let topics: [CommunityTopic]
    let viewCount: Int
    let likeCount: Int
    let commentCount: Int
    let isLiked: Bool
    let isFollowingAuthor: Bool

    func updatingLike(_ liked: Bool) -> CommunityPost {
        CommunityPost(
            id: id,
            authorID: authorID,
            author: author,
            avatarURL: avatarURL,
            content: content,
            createdAt: createdAt,
            imageURLs: imageURLs,
            video: video,
            topics: topics,
            viewCount: viewCount,
            likeCount: max(0, likeCount + (liked ? 1 : -1)),
            commentCount: commentCount,
            isLiked: liked,
            isFollowingAuthor: isFollowingAuthor
        )
    }
}

struct CommunityFeedPage {
    let items: [CommunityPost]
    let page: Int
    let hasMore: Bool
}
