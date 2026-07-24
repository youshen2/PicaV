import SwiftUI

struct MyPage: View {
    @EnvironmentObject private var downloads: VideoDownloadService
    @EnvironmentObject private var settings: AppSettings

    let client: AnimeAPIClient

    var body: some View {
        List {
            accountSection
            librarySection
            applicationSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的")
    }

    private var accountSection: some View {
        Section {
            NavigationLink {
                PlatformAccountSettingsPage()
                    .picaVHidesTabBar()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 42))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(accountSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var librarySection: some View {
        Section("我的内容") {
            NavigationLink {
                LibraryPage(
                    client: client,
                    initialSelection: .favorites
                )
            } label: {
                Label("我的收藏", systemImage: "heart")
            }

            NavigationLink {
                LibraryPage(
                    client: client,
                    initialSelection: .history
                )
            } label: {
                Label("浏览记录", systemImage: "clock.arrow.circlepath")
            }

            NavigationLink {
                VideoDownloadListPage(
                    client: client,
                    scope: .cached
                )
            } label: {
                contentRow(
                    title: "已缓存",
                    systemImage: "tray.full",
                    count: cachedCount
                )
            }

            NavigationLink {
                VideoDownloadListPage(client: client)
            } label: {
                contentRow(
                    title: "下载管理",
                    systemImage: "arrow.down.circle",
                    count: activeDownloadCount
                )
            }
        }
    }

    private var applicationSection: some View {
        Section {
            NavigationLink {
                SettingsPage()
                    .picaVHidesTabBar()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
        }
    }

    private func contentRow(
        title: String,
        systemImage: String,
        count: Int
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if count > 0 {
                Text(count, format: .number)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var accountTitle: String {
        guard settings.isAccountLoggedIn else { return "登录或注册" }
        return settings.accountSession?.displayName ?? "已登录"
    }

    private var accountSubtitle: String {
        settings.isAccountLoggedIn
            ? settings.activePlatform.displayName
            : "登录 \(settings.activePlatform.displayName) 账号"
    }

    private var cachedCount: Int {
        downloads.items.filter { $0.status == .completed }.count
    }

    private var activeDownloadCount: Int {
        downloads.items.filter { $0.status != .completed }.count
    }
}
