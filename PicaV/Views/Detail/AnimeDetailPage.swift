import SwiftUI
import UIKit

struct AnimeDetailPage: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: VideoDownloadService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: AnimeDetailViewModel
    @State private var isSharing = false
    @State private var showsComments = false
    @State private var showsDownloadSelection = false
    @State private var showsCreatorLogin = false
    @State private var playbackRequest: InlinePlaybackRequest?
    @State private var isPageActive = true

    private let client: AnimeAPIClient
    private let preview: Anime?

    init(
        videoID: String,
        preview: Anime? = nil,
        client: AnimeAPIClient,
        startsPlayback _: Bool = false,
        initialEpisodeID: String? = nil,
        initialEpisodeTitle: String? = nil
    ) {
        self.client = client
        self.preview = preview
        _viewModel = StateObject(
            wrappedValue: AnimeDetailViewModel(
                videoID: videoID,
                preview: preview,
                client: client
            )
        )
        _playbackRequest = State(
            initialValue: {
                guard let preview else { return nil }
                return InlinePlaybackRequest(
                    anime: preview,
                    episodeID: initialEpisodeID ?? videoID,
                    episodeTitle: initialEpisodeTitle ?? "正片"
                )
            }()
        )
    }

    var body: some View {
        Group {
            if let detail = viewModel.detail {
                detailList(detail, isPreview: false)
            } else if let preview {
                detailList(placeholderDetail(for: preview), isPreview: true)
            } else {
                LoadStateView(state: viewModel.state) {
                    Task { await viewModel.load(force: true) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .picaVHidesTabBar()
        .navigationTitle(displayedAnime?.title ?? "番剧详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let anime = displayedAnime {
                    if anime.contentKind.supportsPlayback {
                        Button {
                            showsDownloadSelection = true
                        } label: {
                            Image(systemName: downloadToolbarImage)
                        }
                        .accessibilityLabel("下载剧集")
                    }

                    Button {
                        updateFavorite(anime)
                    } label: {
                        if viewModel.isUpdatingFavorite {
                            ProgressView()
                        } else {
                            Image(
                                systemName: isFavorite(anime)
                                    ? "heart.fill"
                                    : "heart"
                            )
                        }
                    }
                    .disabled(viewModel.isUpdatingFavorite)
                    .accessibilityLabel(
                        isFavorite(anime) ? "取消收藏" : "收藏"
                    )

                    Button {
                        isSharing = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享")
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            isPageActive = true
        }
        .onDisappear {
            isPageActive = false
        }
        .sheet(isPresented: $isSharing) {
            if let anime = displayedAnime {
                ActivitySheet(
                    items: [
                        anime.title,
                        viewModel.detail?.synopsis ?? anime.tags.joined(separator: " · ")
                    ]
                )
            }
        }
        .sheet(isPresented: $showsComments) {
            if let anime = displayedAnime {
                AnimeCommentsPage(
                    videoID: anime.id,
                    title: anime.title,
                    client: client
                )
            }
        }
        .sheet(isPresented: $showsDownloadSelection) {
            if let detail = downloadDetail {
                VideoDownloadSelectionSheet(
                    detail: detail,
                    client: client
                )
            }
        }
        .sheet(isPresented: $showsCreatorLogin) {
            NavigationView {
                AccountAuthenticationPage(action: .login)
            }
        }
        .alert(
            "收藏操作失败",
            isPresented: Binding(
                get: { viewModel.favoriteErrorMessage != nil },
                set: { if !$0 { viewModel.favoriteErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.favoriteErrorMessage ?? "")
        }
        .alert(
            "关注操作失败",
            isPresented: Binding(
                get: { viewModel.creatorFollowErrorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.creatorFollowErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.creatorFollowErrorMessage ?? "")
        }
    }

    private var displayedAnime: Anime? {
        viewModel.detail?.anime ?? preview
    }

    private var downloadDetail: AnimeDetail? {
        if let detail = viewModel.detail {
            return detail
        }
        return preview.map(placeholderDetail)
    }

    private var downloadToolbarImage: String {
        guard let detail = downloadDetail else {
            return "arrow.down.circle"
        }
        let episodes = detail.episodes.isEmpty
            ? [
                AnimeEpisode(
                    id: detail.currentEpisodeID,
                    title: "正片",
                    index: 1
                )
            ]
            : detail.episodes
        let allDownloaded = episodes.allSatisfy {
            downloads.item(
                platformID: client.platformID,
                animeID: detail.anime.id,
                episodeID: $0.id
            )?.status == .completed
        }
        return allDownloaded
            ? "checkmark.circle.fill"
            : "arrow.down.circle"
    }

    private func isFavorite(_ anime: Anime) -> Bool {
        if client.isAccountLoggedIn, client.supportsPlatformFavorites,
           let platformValue = viewModel.platformIsFavorite {
            return platformValue
        }
        return library.isFavorite(anime.id)
    }

    private func updateFavorite(_ anime: Anime) {
        let nextValue = !isFavorite(anime)
        guard client.isAccountLoggedIn, client.supportsPlatformFavorites else {
            library.setFavorite(anime, isFavorite: nextValue)
            return
        }

        Task {
            if await viewModel.setPlatformFavorite(nextValue) {
                library.setFavorite(anime, isFavorite: nextValue)
            }
        }
    }

    private func updateCreatorFollowing(_ uploader: AnimeUploader) {
        if client.creatorFollowingRequiresAccount,
           !client.isAccountLoggedIn {
            showsCreatorLogin = true
            return
        }

        Task {
            await viewModel.setCreatorFollowing(
                !(uploader.isFollowed ?? false)
            )
        }
    }

    private func detailList(_ detail: AnimeDetail, isPreview: Bool) -> some View {
        let activePlaybackRequest = playbackRequest
            ?? defaultPlaybackRequest(for: detail)

        return List {
            if detail.anime.contentKind.supportsPlayback {
                InlineAnimePlayerHeader(
                    request: activePlaybackRequest,
                    client: client,
                    library: library,
                    downloads: downloads,
                    isActive: isPageActive && scenePhase == .active
                )
                .id(activePlaybackRequest.id)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                DetailIdentityHeader(detail: detail)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                DetailBackdropHeader(detail: detail)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if isPreview {
                previewStatusSection
            }

            if !isPreview, let uploader = detail.uploader {
                Section("上传者") {
                    DetailUploaderRow(
                        uploader: uploader,
                        canFollow: client.supportsCreatorFollowing
                            && uploader.id != client.currentAccountUserID,
                        isUpdating: viewModel.isUpdatingCreatorFollow
                    ) {
                        updateCreatorFollowing(uploader)
                    }
                }
            }

            if !detail.synopsis.isEmpty {
                Section("剧情简介") {
                    Text(detail.synopsis)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            if !isPreview, detail.anime.contentKind == .comic {
                DetailComicChaptersSection(detail: detail)
            } else if !isPreview, !detail.episodes.isEmpty {
                DetailEpisodesSection(
                    detail: detail,
                    selectedEpisodeID: activePlaybackRequest.episodeID
                ) { episode in
                    startPlayback(
                        anime: detail.anime,
                        episodeID: episode.id,
                        episodeTitle: episode.title
                    )
                }
            }

            if !isPreview,
               detail.anime.contentKind.supportsPlayback,
               client.supportsComments {
                Section {
                    Button {
                        showsComments = true
                    } label: {
                        HStack {
                            Label("查看评论", systemImage: "text.bubble")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !viewModel.recommendations.isEmpty {
                Section("猜你喜欢") {
                    ForEach(viewModel.recommendations.prefix(6)) { anime in
                        AnimeDetailNavigationLink(anime: anime, client: client) {
                            DetailRecommendationRow(anime: anime)
                        }
                        .onNavigate {
                            isPageActive = false
                        }
                    }
                }
            }

            Section("信息") {
                DetailInfoLine(
                    title: "类型",
                    value: detail.anime.contentKind.title
                )
                DetailInfoLine(title: "平台", value: client.platformName)
                if let releaseDate = detail.releaseDate, !releaseDate.isEmpty {
                    DetailInfoLine(title: "发布", value: releaseDate)
                }
                if detail.anime.watchCount > 0 {
                    DetailInfoLine(
                        title: "播放",
                        value: compactCount(detail.anime.watchCount)
                    )
                }
                if detail.anime.likeCount > 0 {
                    DetailInfoLine(
                        title: "喜欢",
                        value: compactCount(detail.anime.likeCount)
                    )
                }
                DetailInfoLine(title: "编号", value: detail.id, monospaced: true)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.load(force: true)
        }
    }

    @ViewBuilder
    private var previewStatusSection: some View {
        Section {
            switch viewModel.state {
            case .idle, .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在载入完整详情…")
                        .foregroundColor(.secondary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Label("详情加载失败", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button("重试") {
                        Task { await viewModel.load(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            case .loaded:
                Text("详情暂不可用，请稍后重试。")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func placeholderDetail(for anime: Anime) -> AnimeDetail {
        AnimeDetail(
            anime: anime,
            synopsis: "",
            episodes: [AnimeEpisode(id: anime.id, title: "正片", index: 1)],
            currentEpisodeID: anime.id,
            videoPath: nil,
            authKey: nil,
            cdnID: nil,
            canWatch: false,
            releaseDate: nil
        )
    }

    private func currentEpisodeTitle(in detail: AnimeDetail) -> String {
        detail.episodes.first {
            $0.id == detail.currentEpisodeID
        }?.title ?? "正片"
    }

    private func defaultPlaybackRequest(
        for detail: AnimeDetail
    ) -> InlinePlaybackRequest {
        InlinePlaybackRequest(
            anime: detail.anime,
            episodeID: detail.currentEpisodeID,
            episodeTitle: currentEpisodeTitle(in: detail)
        )
    }

    private func startPlayback(
        anime: Anime,
        episodeID: String,
        episodeTitle: String
    ) {
        playbackRequest = InlinePlaybackRequest(
            anime: anime,
            episodeID: episodeID,
            episodeTitle: episodeTitle
        )
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
