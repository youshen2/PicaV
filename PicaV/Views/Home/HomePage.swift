import SwiftUI

struct HomePage: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var viewModel: HomeViewModel

    private let client: AnimeAPIClient

    init(client: AnimeAPIClient) {
        self.client = client
        _viewModel = StateObject(wrappedValue: HomeViewModel(client: client))
    }

    var body: some View {
        content
            .navigationTitle(client.platformName)
            .task {
                await viewModel.load()
            }
            .alert(
                "栏目操作失败",
                isPresented: Binding(
                    get: { viewModel.sectionActionErrorMessage != nil },
                    set: {
                        if !$0 {
                            viewModel.sectionActionErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.sectionActionErrorMessage ?? "")
            }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if viewModel.channels.count > 1 {
                    Picker(
                        "内容频道",
                        selection: channelBinding
                    ) {
                        ForEach(viewModel.channels) { channel in
                            Text(channel.title).tag(channel.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                channelContent
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .refreshable {
            await viewModel.load(force: true)
        }
    }

    @ViewBuilder
    private var channelContent: some View {
        if viewModel.state == .loading, viewModel.hero == nil {
            LoadStateView(state: .loading)
        } else if case .failed = viewModel.state, viewModel.hero == nil {
            LoadStateView(state: viewModel.state) {
                Task { await viewModel.load(force: true) }
            }
        } else {
            Group {
                if let hero = viewModel.hero {
                    HeroAnimeView(anime: hero, client: client)
                }

                if viewModel.isFeaturedChannelSelected,
                   !visibleHistory.isEmpty {
                    ContinueWatchingSection(
                        entries: Array(visibleHistory.prefix(8)),
                        client: client
                    )
                }

                if !viewModel.sections.isEmpty {
                    ForEach(viewModel.sections) { section in
                        PlatformHomeSection(
                            section: section,
                            client: client,
                            isShuffling: viewModel.shufflingSectionIDs
                                .contains(section.id)
                        ) {
                            Task { await viewModel.shuffle(section) }
                        }
                    }
                } else {
                    if !viewModel.popular.isEmpty {
                        HomeSectionHeader(title: "本周热播", subtitle: "大家都在追")
                        HorizontalAnimeRail(items: viewModel.popular, client: client)
                    }

                    if !viewModel.latest.isEmpty {
                        HomeSectionHeader(title: "最新更新", subtitle: "新一集已送达")
                        AnimeGridView(items: viewModel.latest, client: client)
                            .padding(.horizontal)
                    }
                }

                if viewModel.hero == nil {
                    EmptyStateView(
                        systemImage: "sparkles.tv",
                        title: "暂时没有番剧",
                        message: "下拉刷新，或前往设置检查服务器地址。"
                    )
                }
            }
        }
    }

    private var channelBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedChannelID },
            set: { channelID in
                Task {
                    await viewModel.selectChannel(channelID)
                }
            }
        )
    }

    private var visibleHistory: [WatchHistoryEntry] {
        library.history.filter { $0.anime.contentKind != .comic }
    }
}

private struct HeroAnimeView: View {
    let anime: Anime
    let client: AnimeAPIClient

    var body: some View {
        AnimeDetailNavigationLink(anime: anime, client: client) {
            ZStack(alignment: .bottomLeading) {
                RemoteImageView(url: anime.bannerURL ?? anime.coverURL, maxPixelSize: 1_400)
                    .frame(height: 238)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("正在热播")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                    Text(anime.title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if !anime.tags.isEmpty {
                            Text(anime.tags.prefix(3).joined(separator: " · "))
                        }
                        if anime.watchCount > 0 {
                            Label(compactCount(anime.watchCount), systemImage: "play.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

private struct HomeSectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.bold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}

private struct PlatformHomeSection: View {
    let section: AnimeHomeSection
    let client: AnimeAPIClient
    let isShuffling: Bool
    let onShuffle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(
                title: section.title,
                subtitle: section.subtitle
            )

            switch section.layout {
            case .portrait, .portraitRail:
                HorizontalAnimeRail(items: section.items, client: client)
            case .landscape, .featuredLandscape, .compactLandscape:
                HorizontalLandscapeAnimeRail(items: section.items, client: client)
            }

            if section.actions != nil {
                HomeSectionActionsBar(
                    section: section,
                    client: client,
                    isShuffling: isShuffling,
                    onShuffle: onShuffle
                )
                .padding(.horizontal)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: section.items)
    }
}

private struct HomeSectionActionsBar: View {
    let section: AnimeHomeSection
    let client: AnimeAPIClient
    let isShuffling: Bool
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                HomeSectionMorePage(section: section, client: client)
            } label: {
                Label("查看更多", systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 22)

            Button(action: onShuffle) {
                HStack(spacing: 7) {
                    if isShuffling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text("换一批")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
            }
            .buttonStyle(.plain)
            .disabled(isShuffling)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundColor(.secondary)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HorizontalAnimeRail: View {
    let items: [Anime]
    let client: AnimeAPIClient

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(items) { anime in
                    AnimeDetailNavigationLink(anime: anime, client: client) {
                        AnimeCardView(anime: anime)
                            .frame(width: AnimeCardMetrics.width)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct HorizontalLandscapeAnimeRail: View {
    let items: [Anime]
    let client: AnimeAPIClient

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(items) { anime in
                    AnimeDetailNavigationLink(anime: anime, client: client) {
                        VStack(alignment: .leading, spacing: 8) {
                            RemoteImageView(
                                urls: [anime.bannerURL, anime.coverURL],
                                maxPixelSize: 720
                            )
                            .frame(width: 220, height: 124)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )
                            .overlay(alignment: .bottomLeading) {
                                if let episode = anime.episodeLabel,
                                   !episode.isEmpty {
                                    Text(episode)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.7))
                                        .clipShape(Capsule())
                                        .padding(7)
                                }
                            }

                            Text(anime.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                                .lineLimit(2)

                            if anime.watchCount > 0 {
                                Label(
                                    compactCount(anime.watchCount),
                                    systemImage: "play.fill"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 220, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct ContinueWatchingSection: View {
    let entries: [WatchHistoryEntry]
    let client: AnimeAPIClient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(title: "继续观看", subtitle: "接着上次的进度")
                .padding(.bottom, 0)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(entries) { entry in
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
                            VStack(alignment: .leading, spacing: 8) {
                                RemoteImageView(
                                    url: entry.anime.bannerURL ?? entry.anime.coverURL,
                                    maxPixelSize: 640
                                )
                                .frame(width: 210, height: 118)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .bottom) {
                                    ProgressView(value: entry.progressFraction)
                                        .tint(.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.bottom, 5)
                                }
                                Text(entry.anime.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(entry.episodeTitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 210, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
