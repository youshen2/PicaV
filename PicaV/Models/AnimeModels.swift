import Foundation

enum AnimeContentKind: String, Codable, Hashable {
    case anime
    case video
    case comic

    var title: String {
        switch self {
        case .anime: return "动漫"
        case .video: return "视频"
        case .comic: return "漫画"
        }
    }

    var supportsPlayback: Bool {
        self != .comic
    }
}

enum AnimeSort: Int, CaseIterable, Identifiable {
    case latest = 1
    case popular = 2
    case mostLiked = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .latest: return "最新"
        case .popular: return "热播"
        case .mostLiked: return "好评"
        }
    }
}

struct AnimeCategory: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let imageURL: URL?

    init(id: String, title: String, imageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.imageURL = imageURL
    }
}

struct Anime: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let coverURL: URL?
    let bannerURL: URL?
    let tags: [String]
    let watchCount: Int
    let likeCount: Int
    let episodeLabel: String?
    let isPremium: Bool
    let contentKind: AnimeContentKind

    init(
        id: String,
        title: String,
        coverURL: URL? = nil,
        bannerURL: URL? = nil,
        tags: [String] = [],
        watchCount: Int = 0,
        likeCount: Int = 0,
        episodeLabel: String? = nil,
        isPremium: Bool = false,
        contentKind: AnimeContentKind = .anime
    ) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.bannerURL = bannerURL
        self.tags = tags
        self.watchCount = watchCount
        self.likeCount = likeCount
        self.episodeLabel = episodeLabel
        self.isPremium = isPremium
        self.contentKind = contentKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        coverURL = try container.decodeIfPresent(URL.self, forKey: .coverURL)
        bannerURL = try container.decodeIfPresent(URL.self, forKey: .bannerURL)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        watchCount = try container.decodeIfPresent(Int.self, forKey: .watchCount) ?? 0
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        episodeLabel = try container.decodeIfPresent(
            String.self,
            forKey: .episodeLabel
        )
        isPremium = try container.decodeIfPresent(
            Bool.self,
            forKey: .isPremium
        ) ?? false
        contentKind = try container.decodeIfPresent(
            AnimeContentKind.self,
            forKey: .contentKind
        ) ?? .anime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(coverURL, forKey: .coverURL)
        try container.encodeIfPresent(bannerURL, forKey: .bannerURL)
        try container.encode(tags, forKey: .tags)
        try container.encode(watchCount, forKey: .watchCount)
        try container.encode(likeCount, forKey: .likeCount)
        try container.encodeIfPresent(episodeLabel, forKey: .episodeLabel)
        try container.encode(isPremium, forKey: .isPremium)
        try container.encode(contentKind, forKey: .contentKind)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case coverURL
        case bannerURL
        case tags
        case watchCount
        case likeCount
        case episodeLabel
        case isPremium
        case contentKind
    }
}

struct AnimeEpisode: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let index: Int

    init(id: String, title: String, index: Int) {
        self.id = id
        self.title = title
        self.index = index
    }
}

struct CDNLine: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let domain: String?
}

struct AnimeUploader: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let avatarURL: URL?
    let biography: String?
    let isFollowed: Bool?
}

struct AnimeDetail: Identifiable, Codable, Hashable {
    let anime: Anime
    let synopsis: String
    let episodes: [AnimeEpisode]
    let currentEpisodeID: String
    let videoPath: String?
    let authKey: String?
    let cdnID: String?
    let canWatch: Bool
    let releaseDate: String?
    let isFavorite: Bool?
    let uploader: AnimeUploader?

    var id: String { anime.id }

    init(
        anime: Anime,
        synopsis: String,
        episodes: [AnimeEpisode],
        currentEpisodeID: String,
        videoPath: String?,
        authKey: String?,
        cdnID: String?,
        canWatch: Bool,
        releaseDate: String?,
        isFavorite: Bool? = nil,
        uploader: AnimeUploader? = nil
    ) {
        self.anime = anime
        self.synopsis = synopsis
        self.episodes = episodes
        self.currentEpisodeID = currentEpisodeID
        self.videoPath = videoPath
        self.authKey = authKey
        self.cdnID = cdnID
        self.canWatch = canWatch
        self.releaseDate = releaseDate
        self.isFavorite = isFavorite
        self.uploader = uploader
    }

    func replacingUploader(_ uploader: AnimeUploader?) -> AnimeDetail {
        AnimeDetail(
            anime: anime,
            synopsis: synopsis,
            episodes: episodes,
            currentEpisodeID: currentEpisodeID,
            videoPath: videoPath,
            authKey: authKey,
            cdnID: cdnID,
            canWatch: canWatch,
            releaseDate: releaseDate,
            isFavorite: isFavorite,
            uploader: uploader
        )
    }
}

struct AnimeComment: Identifiable, Codable, Hashable {
    let id: String
    let authorID: String?
    let author: String
    let avatarURL: URL?
    let content: String
    let createdAt: String?
    let likeCount: Int
    let replyCount: Int
    let isLiked: Bool
    let imageURL: URL?
    let replies: [AnimeComment]
}

struct AnimePage {
    let items: [Anime]
    let page: Int
    let hasMore: Bool
}

enum AnimeHomeSectionLayout: Int, Hashable {
    case landscape = 1
    case portrait = 2
    case portraitRail = 3
    case featuredLandscape = 4
    case compactLandscape = 5

    init(platformValue: Int?) {
        self = platformValue.flatMap(Self.init(rawValue:)) ?? .landscape
    }
}

struct AnimeHomeSection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let layout: AnimeHomeSectionLayout
    let items: [Anime]
    let actions: PlatformHomeSectionActions?

    init(
        id: String,
        title: String,
        subtitle: String?,
        layout: AnimeHomeSectionLayout,
        items: [Anime],
        actions: PlatformHomeSectionActions? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.layout = layout
        self.items = items
        self.actions = actions
    }

    func replacingItems(_ items: [Anime]) -> AnimeHomeSection {
        AnimeHomeSection(
            id: id,
            title: title,
            subtitle: subtitle,
            layout: layout,
            items: items,
            actions: actions
        )
    }
}

struct PlatformHomeSectionActions: Hashable {
    let sectionID: String
    let sortType: Int
    let changePageSize: Int
}

struct WatchHistoryEntry: Identifiable, Codable, Hashable {
    var id: String { "\(anime.id)-\(episodeID)" }

    let anime: Anime
    let episodeID: String
    let episodeTitle: String
    let progress: Double
    let duration: Double
    let updatedAt: Date

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(progress / duration, 0), 1)
    }

    var progressText: String {
        guard progress > 0 else { return "刚刚开始" }
        return "\(Self.timeText(progress)) / \(Self.timeText(duration))"
    }

    private static func timeText(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "00:00" }
        let seconds = Int(value.rounded(.down))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

extension Anime {
    static let preview = Anime(
        id: "preview-1",
        title: "星海与夏日",
        tags: ["奇幻", "冒险"],
        watchCount: 1_286_000,
        likeCount: 38_000,
        episodeLabel: "更新至 12 集"
    )
}
