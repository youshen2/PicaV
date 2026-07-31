import Combine
import Foundation

struct PlaybackSource: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var detail: AnimeDetail?
    @Published private(set) var sources: [PlaybackSource] = []
    @Published private(set) var selectedSourceID: String?
    @Published private(set) var resumeTime: TimeInterval = 0

    var episodeTitle: String {
        detail?.episodes.first {
            $0.id == episodeID
        }?.title ?? requestedEpisodeTitle
    }

    var selectedSourceIndex: Int {
        guard let selectedSourceID,
              let index = sources.firstIndex(where: { $0.id == selectedSourceID }) else {
            return 0
        }
        return index
    }

    init(
        anime: Anime,
        episodeID: String,
        episodeTitle: String,
        initialDetail: AnimeDetail? = nil,
        client: AnimeAPIClient,
        library: LibraryStore,
        downloads: VideoDownloadService,
        onPlaybackEnded: @escaping () -> Void = {}
    ) {
        self.anime = anime
        self.episodeID = episodeID
        requestedEpisodeTitle = episodeTitle
        self.initialDetail = initialDetail
        self.client = client
        self.library = library
        self.downloads = downloads
        self.onPlaybackEnded = onPlaybackEnded
    }

    func prepare() async {
        guard state == .idle || isFailure else { return }
        state = .loading

        if let localURL = downloads.localPlaybackURL(
            platformID: client.platformID,
            animeID: anime.id,
            episodeID: episodeID
        ) {
            sources = [
                PlaybackSource(
                    id: Self.localSourceID,
                    name: "本地",
                    url: localURL
                )
            ]
            selectedSourceID = Self.localSourceID
            resumeTime = savedResumeTime()
            state = .loaded
            return
        }

        do {
            async let linesTask = client.fetchCDNLines()
            let loadedDetail: AnimeDetail
            if let initialDetail {
                loadedDetail = initialDetail
            } else {
                loadedDetail = try await client.fetchDetail(
                    videoID: episodeID,
                    fallbackAnime: anime
                )
            }
            let loadedLines = (try? await linesTask) ?? []
            let loadedSources = try playbackSources(
                detail: loadedDetail,
                lines: loadedLines
            )

            detail = loadedDetail
            sources = loadedSources
            selectedSourceID = preferredSourceID(
                detail: loadedDetail,
                sources: loadedSources
            )
            resumeTime = savedResumeTime()
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            guard !Task.isCancelled else {
                state = .idle
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    func selectSource(at index: Int) {
        guard sources.indices.contains(index) else { return }
        let source = sources[index]
        selectedSourceID = source.id
        if source.id != Self.localSourceID {
            client.setPreferredCDNID(source.id)
        }
    }

    func progressDidChange(currentTime: TimeInterval, totalTime: TimeInterval) {
        guard currentTime.isFinite, totalTime.isFinite else { return }
        let replayTolerance = min(
            2,
            max(totalTime * 0.02, 0.1)
        )
        if didSignalPlaybackEnd,
           currentTime + replayTolerance < currentProgress {
            didSignalPlaybackEnd = false
        }
        currentProgress = max(currentTime, 0)
        currentDuration = max(totalTime, 0)
        if abs(currentProgress - lastPersistedProgress) >= 10 {
            persistProgress()
        }
    }

    func playbackDidFinish() {
        guard !didSignalPlaybackEnd else { return }
        didSignalPlaybackEnd = true
        if currentDuration > 0 {
            currentProgress = max(currentProgress, currentDuration)
        }
        persistProgress()
        if client.autoplayNextEpisode {
            onPlaybackEnded()
        }
    }

    func stop() {
        persistProgress()
    }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private func playbackSources(
        detail: AnimeDetail,
        lines: [CDNLine]
    ) throws -> [PlaybackSource] {
        let candidates: [CDNLine]
        if lines.isEmpty {
            candidates = [
                CDNLine(
                    id: detail.cdnID ?? "default",
                    name: "默认线路",
                    domain: nil
                )
            ]
        } else {
            candidates = lines
        }

        let result = candidates.compactMap { line -> PlaybackSource? in
            guard let url = try? client.playbackURL(for: detail, cdnID: line.id) else {
                return nil
            }
            return PlaybackSource(id: line.id, name: line.name, url: url)
        }
        guard !result.isEmpty else {
            throw AnimeAPIError.playbackUnavailable
        }
        return result
    }

    private func preferredSourceID(
        detail: AnimeDetail,
        sources: [PlaybackSource]
    ) -> String? {
        let preferred = client.preferredCDNID ?? detail.cdnID
        if let preferred, sources.contains(where: { $0.id == preferred }) {
            return preferred
        }
        return sources.first?.id
    }

    private func savedResumeTime() -> TimeInterval {
        guard let entry = library.history.first(where: {
            $0.anime.id == anime.id && $0.episodeID == episodeID
        }), entry.progressFraction < 0.98 else {
            return 0
        }
        return max(entry.progress, 0)
    }

    private func persistProgress() {
        guard currentProgress > 0 else { return }
        library.record(
            anime: detail?.anime ?? anime,
            episodeID: episodeID,
            episodeTitle: episodeTitle,
            progress: currentProgress,
            duration: currentDuration
        )
        lastPersistedProgress = currentProgress
    }

    private let anime: Anime
    private let episodeID: String
    private let requestedEpisodeTitle: String
    private let initialDetail: AnimeDetail?
    private let client: AnimeAPIClient
    private let library: LibraryStore
    private let downloads: VideoDownloadService
    private let onPlaybackEnded: () -> Void
    private var currentProgress: TimeInterval = 0
    private var currentDuration: TimeInterval = 0
    private var lastPersistedProgress: TimeInterval = -10
    private var didSignalPlaybackEnd = false
    private static let localSourceID = "__local_download__"
}
