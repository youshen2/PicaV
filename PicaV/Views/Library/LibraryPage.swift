import SwiftUI

struct LibraryPage: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel: PlatformLibraryViewModel
    @State private var selection: LibrarySection

    private let client: AnimeAPIClient

    init(
        client: AnimeAPIClient,
        initialSelection: LibrarySection = .favorites
    ) {
        self.client = client
        _selection = State(initialValue: initialSelection)
        _viewModel = StateObject(
            wrappedValue: PlatformLibraryViewModel(client: client)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("资料库", selection: $selection) {
                ForEach(LibrarySection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if usesPlatformData {
                platformContent
            } else {
                localContent
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(selection.navigationTitle)
        .picaVHidesTabBar()
        .task(id: refreshIdentity) {
            if usesPlatformData {
                await viewModel.load(selection)
            } else if selection == .history {
                await library.refreshHistoryArtwork(using: client)
            }
        }
        .onAppear {
            guard usesPlatformData else { return }
            Task { await viewModel.load(selection, force: true) }
        }
        .onChange(of: settings.platformID) { _ in
            viewModel.reset()
        }
        .onChange(of: settings.isAccountLoggedIn) { _ in
            viewModel.reset()
        }
    }

    @ViewBuilder
    private var platformContent: some View {
        let state = viewModel.state(for: selection)
        let items = viewModel.items(for: selection)

        switch state {
        case .idle, .loading:
            LoadStateView(state: .loading)
                .frame(maxHeight: .infinity)
        case .failed:
            LoadStateView(state: state) {
                Task { await viewModel.load(selection, force: true) }
            }
            .frame(maxHeight: .infinity)
        case .loaded where items.isEmpty:
            EmptyStateView(
                systemImage: selection == .favorites
                    ? "heart"
                    : "clock.arrow.circlepath",
                title: selection == .favorites
                    ? "平台收藏还是空的"
                    : "平台还没有浏览记录",
                message: selection == .favorites
                    ? "在详情页点按爱心，条目会同步到当前平台。"
                    : "浏览或播放内容后，平台记录会显示在这里。"
            )
            .frame(maxHeight: .infinity)
        case .loaded:
            if selection == .favorites {
                platformFavorites(items)
            } else {
                platformHistory(items)
            }
        }
    }

    private func platformFavorites(_ items: [Anime]) -> some View {
        ScrollView {
            AnimeGridView(
                items: items,
                client: client
            ) { anime in
                Task {
                    await viewModel.loadMoreIfNeeded(
                        .favorites,
                        currentItem: anime
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.load(.favorites, force: true)
        }
    }

    private func platformHistory(_ items: [Anime]) -> some View {
        List {
            ForEach(items) { anime in
                AnimeDetailNavigationLink(anime: anime, client: client) {
                    PlatformHistoryRow(anime: anime)
                }
                .buttonStyle(.plain)
                .onAppear {
                    Task {
                        await viewModel.loadMoreIfNeeded(
                            .history,
                            currentItem: anime
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.load(.history, force: true)
        }
    }

    @ViewBuilder
    private var localContent: some View {
        VStack(spacing: 0) {
            if client.platformLibraryRequiresAccount {
                accountBanner
            }

            if selection == .favorites {
                localFavorites
            } else {
                localHistory
            }
        }
    }

    private var accountBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("当前显示本机记录")
                    .font(.subheadline.weight(.semibold))
                Text("登录后同步\(selection.navigationTitle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            NavigationLink {
                AccountAuthenticationPage(action: .login)
            } label: {
                Text("登录")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var localFavorites: some View {
        if visibleLocalFavorites.isEmpty {
            EmptyStateView(
                systemImage: "heart",
                title: "还没有收藏",
                message: "在番剧详情页点按爱心，喜欢的作品会保存在本机。"
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                AnimeGridView(items: visibleLocalFavorites, client: client)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var localHistory: some View {
        if visibleLocalHistory.isEmpty {
            EmptyStateView(
                systemImage: "clock.arrow.circlepath",
                title: "还没有观看记录",
                message: "开始播放后，进度会自动保存在这台设备上。"
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(visibleLocalHistory) { entry in
                    NavigationLink {
                        AnimeDetailPage(
                            videoID: entry.anime.id,
                            preview: entry.anime,
                            client: client,
                            startsPlayback: true,
                            initialEpisodeID: entry.episodeID,
                            initialEpisodeTitle: entry.episodeTitle
                        )
                    } label: {
                        LocalHistoryRow(entry: entry)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            library.removeHistory(entry)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var usesPlatformData: Bool {
        settings.isAccountLoggedIn
            && ((selection == .favorites && client.supportsPlatformFavorites)
                || (selection == .history && client.supportsPlatformHistory))
    }

    private var refreshIdentity: String {
        [
            settings.platformID.rawValue,
            settings.isAccountLoggedIn ? "account" : "local",
            selection.rawValue
        ].joined(separator: "|")
    }

    private var visibleLocalFavorites: [Anime] {
        library.favorites.filter { $0.contentKind != .comic }
    }

    private var visibleLocalHistory: [WatchHistoryEntry] {
        library.history.filter { $0.anime.contentKind != .comic }
    }
}

private struct PlatformHistoryRow: View {
    let anime: Anime

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImageView(
                urls: [anime.coverURL, anime.bannerURL],
                maxPixelSize: 500,
                contentMode: .fill
            )
            .frame(width: 76, height: 102)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(anime.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if let episodeLabel = anime.episodeLabel {
                    Text(episodeLabel)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if !anime.tags.isEmpty {
                    Text(anime.tags.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct LocalHistoryRow: View {
    let entry: WatchHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImageView(
                urls: [entry.anime.coverURL, entry.anime.bannerURL],
                maxPixelSize: 500,
                contentMode: .fill
            )
            .frame(width: 64, height: 86)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.anime.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(entry.episodeTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                ProgressView(value: entry.progressFraction)
                    .tint(.accentColor)
                Text(entry.progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
