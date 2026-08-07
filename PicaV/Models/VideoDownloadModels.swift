import Foundation

enum VideoDownloadStatus: String, Codable, Hashable {
    case preparing
    case downloading
    case paused
    case completed
    case failed
}

struct VideoDownloadItem: Identifiable, Codable, Hashable {
    let id: String
    let platformID: AnimePlatformID
    let anime: Anime
    let episodeID: String
    let episodeTitle: String
    var localPath: String?
    var progress: Double
    var status: VideoDownloadStatus
    var errorMessage: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        platformID: AnimePlatformID,
        anime: Anime,
        episodeID: String,
        episodeTitle: String
    ) {
        id = Self.identifier(
            platformID: platformID,
            animeID: anime.id,
            episodeID: episodeID
        )
        self.platformID = platformID
        self.anime = anime
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        localPath = nil
        progress = 0
        status = .preparing
        errorMessage = nil
        createdAt = Date()
        updatedAt = Date()
    }

    var statusText: String {
        switch status {
        case .preparing:
            return "正在解析播放源"
        case .downloading:
            return "下载中 \(Int(progress * 100))%"
        case .paused:
            return "已暂停 \(Int(progress * 100))%"
        case .completed:
            return "已下载 MP4"
        case .failed:
            return errorMessage ?? "下载失败"
        }
    }

    static func identifier(
        platformID: AnimePlatformID,
        animeID: String,
        episodeID: String
    ) -> String {
        [platformID.rawValue, animeID, episodeID]
            .joined(separator: "|")
    }
}
