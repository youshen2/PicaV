import Foundation

enum AnimeSearchScope: String, CaseIterable, Identifiable {
    case anime
    case video
    case shortVideo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anime: return "动漫"
        case .video: return "视频"
        case .shortVideo: return "短视频"
        }
    }

    var prompt: String {
        switch self {
        case .anime: return "番剧名、角色或标签"
        case .video, .shortVideo: return "标题、上传者或标签"
        }
    }

    var contentKind: AnimeContentKind {
        switch self {
        case .anime: return .anime
        case .video, .shortVideo: return .video
        }
    }
}
