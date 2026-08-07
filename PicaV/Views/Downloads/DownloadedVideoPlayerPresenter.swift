import Combine
import Foundation
import SwiftUI

struct DownloadedVideoPlaybackRequest: Identifiable, Hashable {
    let item: VideoDownloadItem
    let localURL: URL
    let recordsHistory: Bool

    var id: String { item.id }
}

struct DownloadedVideoPlayerPresenter: View {
    @StateObject private var session: DownloadedVideoPlaybackSession

    private let request: DownloadedVideoPlaybackRequest
    private let onDismiss: () -> Void

    init(
        request: DownloadedVideoPlaybackRequest,
        library: LibraryStore,
        onDismiss: @escaping () -> Void
    ) {
        self.request = request
        self.onDismiss = onDismiss
        _session = StateObject(
            wrappedValue: DownloadedVideoPlaybackSession(
                item: request.item,
                library: library,
                recordsHistory: request.recordsHistory
            )
        )
    }

    var body: some View {
        KSPlayerContainerView(
            sources: [
                PlaybackSource(
                    id: "download-\(request.item.id)",
                    name: "本地",
                    url: request.localURL
                )
            ],
            title: playbackTitle,
            initialSourceIndex: 0,
            resumeTime: session.resumeTime,
            isActive: true,
            startsInFullScreen: true,
            onProgress: { currentTime, totalTime in
                session.progressDidChange(
                    currentTime: currentTime,
                    totalTime: totalTime
                )
            },
            onPlaybackEnded: {
                session.playbackDidFinish()
            },
            onSourceChange: { _ in },
            onFullScreenChange: { isFullScreen in
                guard !isFullScreen else { return }
                session.stop()
                onDismiss()
            }
        )
        .frame(width: 1, height: 1)
        .offset(x: -2, y: -2)
        .clipped()
        .onDisappear {
            session.stop()
        }
    }

    private var playbackTitle: String {
        guard !request.item.episodeTitle.isEmpty else {
            return request.item.anime.title
        }
        return "\(request.item.anime.title) · \(request.item.episodeTitle)"
    }
}

@MainActor
private final class DownloadedVideoPlaybackSession: ObservableObject {
    let resumeTime: TimeInterval

    init(
        item: VideoDownloadItem,
        library: LibraryStore,
        recordsHistory: Bool
    ) {
        self.item = item
        self.library = library
        self.recordsHistory = recordsHistory
        if recordsHistory,
           let entry = library.history.first(where: {
               $0.anime.id == item.anime.id
                   && $0.episodeID == item.episodeID
           }),
           entry.progressFraction < 0.98 {
            resumeTime = max(entry.progress, 0)
        } else {
            resumeTime = 0
        }
    }

    func progressDidChange(
        currentTime: TimeInterval,
        totalTime: TimeInterval
    ) {
        guard currentTime.isFinite, totalTime.isFinite else { return }
        currentProgress = max(currentTime, 0)
        currentDuration = max(totalTime, 0)
        if abs(currentProgress - lastPersistedProgress) >= 10 {
            persistProgress()
        }
    }

    func playbackDidFinish() {
        if currentDuration > 0 {
            currentProgress = max(currentProgress, currentDuration)
        }
        persistProgress()
    }

    func stop() {
        guard !didStop else { return }
        didStop = true
        persistProgress()
    }

    private func persistProgress() {
        guard recordsHistory, currentProgress > 0 else { return }
        library.record(
            anime: item.anime,
            episodeID: item.episodeID,
            episodeTitle: item.episodeTitle,
            progress: currentProgress,
            duration: currentDuration
        )
        lastPersistedProgress = currentProgress
    }

    private let item: VideoDownloadItem
    private let library: LibraryStore
    private let recordsHistory: Bool
    private var currentProgress: TimeInterval = 0
    private var currentDuration: TimeInterval = 0
    private var lastPersistedProgress: TimeInterval = -10
    private var didStop = false
}
