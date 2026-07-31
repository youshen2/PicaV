import SwiftUI

struct SettingsPage: View {
    @State private var searchText = ""

    var body: some View {
        List {
            ForEach(SettingsGroup.allCases) { group in
                let destinations = filteredDestinations.filter { $0.group == group }
                if !destinations.isEmpty {
                    Section(header: Text(group.title)) {
                        ForEach(destinations) { destination in
                            NavigationLink {
                                destinationView(destination)
                            } label: {
                                SettingsNavigationLabel(destination: destination)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .searchable(text: $searchText, prompt: "搜索设置")
        .overlay {
            if filteredDestinations.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "没有匹配的设置",
                    message: "换一个关键词试试。"
                )
            }
        }
    }

    private var filteredDestinations: [SettingsDestination] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsDestination.allCases }
        return SettingsDestination.allCases.filter { destination in
            destination.searchText.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: SettingsDestination) -> some View {
        switch destination {
        case .platforms:
            PlatformSelectionPage()
        case .account:
            PlatformAccountSettingsPage()
        case .browsing:
            BrowsingSettingsPage()
        case .playback:
            PlaybackSettingsPage()
        case .storage:
            StorageSettingsPage()
        case .network:
            NetworkSettingsPage()
        case .about:
            AboutSettingsPage()
        }
    }
}

private enum SettingsGroup: Int, CaseIterable, Identifiable {
    case account
    case browsing
    case content
    case application

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .account: return "账号"
        case .browsing: return "浏览与播放"
        case .content: return "内容与数据"
        case .application: return "网络与应用"
        }
    }
}

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case platforms
    case account
    case browsing
    case playback
    case storage
    case network
    case about

    var id: String { rawValue }

    var group: SettingsGroup {
        switch self {
        case .platforms, .account: return .account
        case .browsing, .playback: return .browsing
        case .storage: return .content
        case .network, .about: return .application
        }
    }

    var title: String {
        switch self {
        case .platforms: return "平台与数据源"
        case .account: return "平台账号"
        case .browsing: return "图片加载"
        case .playback: return "详情与播放"
        case .storage: return "存储与历史"
        case .network: return "网络"
        case .about: return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .platforms: return "选择番剧平台并独立保存配置"
        case .account: return "登录、注册与当前会话"
        case .browsing: return "代理策略与重新载入"
        case .playback: return "线路偏好和自动连播"
        case .storage: return "图片缓存、收藏和观看记录"
        case .network: return "应用代理、服务器地址与 API 配置"
        case .about: return "应用与平台适配信息"
        }
    }

    var systemImage: String {
        switch self {
        case .platforms: return "square.stack.3d.up"
        case .account: return "person.2"
        case .browsing: return "house"
        case .playback: return "play.rectangle"
        case .storage: return "internaldrive"
        case .network: return "network"
        case .about: return "info.circle"
        }
    }

    var searchText: String {
        [title, subtitle, rawValue].joined(separator: " ")
    }
}

private struct SettingsNavigationLabel: View {
    let destination: SettingsDestination

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(destination.title)
                    .foregroundColor(.primary)
                Text(destination.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } icon: {
            Image(systemName: destination.systemImage)
        }
    }
}
