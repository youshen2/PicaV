import SwiftUI

struct InlinePlaybackRequest: Identifiable, Hashable {
    let anime: Anime
    let episodeID: String
    let episodeTitle: String

    var id: String {
        "\(anime.id)-\(episodeID)"
    }
}

struct InlineAnimePlayerHeader: View {
    @StateObject private var viewModel: PlayerViewModel

    private let isActive: Bool

    init(
        request: InlinePlaybackRequest,
        client: AnimeAPIClient,
        library: LibraryStore,
        downloads: VideoDownloadService,
        isActive: Bool
    ) {
        _viewModel = StateObject(
            wrappedValue: PlayerViewModel(
                anime: request.anime,
                episodeID: request.episodeID,
                episodeTitle: request.episodeTitle,
                client: client,
                library: library,
                downloads: downloads
            )
        )
        self.isActive = isActive
    }

    var body: some View {
        ZStack {
            Color.black

            if !viewModel.sources.isEmpty {
                KSPlayerContainerView(
                    sources: viewModel.sources,
                    title: viewModel.episodeTitle,
                    initialSourceIndex: viewModel.selectedSourceIndex,
                    resumeTime: viewModel.resumeTime,
                    isActive: isActive,
                    onProgress: { currentTime, totalTime in
                        viewModel.progressDidChange(
                            currentTime: currentTime,
                            totalTime: totalTime
                        )
                    },
                    onSourceChange: { index in
                        viewModel.selectSource(at: index)
                    }
                )
            } else {
                placeholder
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .task {
            await viewModel.prepare()
        }
        .onDisappear {
            viewModel.stop()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正在播放 \(viewModel.episodeTitle)")
    }

    @ViewBuilder
    private var placeholder: some View {
        switch viewModel.state {
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundColor(.yellow)
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await viewModel.prepare() }
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding()
        default:
            ProgressView()
                .tint(.white)
        }
    }
}
