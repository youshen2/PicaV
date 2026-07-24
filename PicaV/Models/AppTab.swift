import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case explore
    case community
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .explore: return "发现"
        case .community: return "社区"
        case .profile: return "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .explore: return "sparkles.tv"
        case .community: return "person.3"
        case .profile: return "person.crop.circle"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "sparkles.tv.fill"
        case .community: return "person.3.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}
