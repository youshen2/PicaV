import AVFoundation
import Combine
import Foundation

@MainActor
final class VideoDownloadService: NSObject, ObservableObject {
    static let backgroundSessionIdentifier =
        "work.picav.video-downloads"

    @Published private(set) var items: [VideoDownloadItem]

    static func setBackgroundEventsCompletionHandler(
        _ completionHandler: @escaping () -> Void
    ) {
        backgroundEventsCompletionHandler = completionHandler
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        fileStore = DownloadFileStore(fileManager: fileManager)
        persistence = VideoDownloadPersistence(defaults: defaults)
        progressThrottler = DownloadProgressThrottler()
        items = Self.loadItems(defaults: defaults)
        super.init()

        progressThrottler.setOnFlush { [weak self] updates in
            Task { @MainActor [weak self] in
                self?.updateProgress(updates)
            }
        }
        _ = assetSession
        restoreSystemTasks()
        validateCompletedItems()
    }

    func enqueue(
        anime: Anime,
        episodes: [AnimeEpisode],
        client: AnimeAPIClient
    ) async -> Int {
        var queuedCount = 0
        for episode in episodes {
            guard !Task.isCancelled else { break }
            let id = VideoDownloadItem.identifier(
                platformID: client.platformID,
                animeID: anime.id,
                episodeID: episode.id
            )
            if let existing = item(withID: id),
               [.preparing, .downloading, .paused, .completed]
                .contains(existing.status) {
                continue
            }

            let item = VideoDownloadItem(
                platformID: client.platformID,
                anime: anime,
                episodeID: episode.id,
                episodeTitle: episode.title
            )
            replaceOrInsert(item)
            queuedCount += 1

            do {
                try await resolveAndStart(
                    itemID: id,
                    anime: anime,
                    episodeID: episode.id,
                    client: client
                )
            } catch is CancellationError {
                updateItem(id) {
                    $0.status = .paused
                    $0.errorMessage = nil
                }
                break
            } catch {
                updateItem(id) {
                    $0.status = .failed
                    $0.errorMessage = error.localizedDescription
                }
            }
        }
        return queuedCount
    }

    func retry(
        _ item: VideoDownloadItem,
        client: AnimeAPIClient
    ) async {
        updateItem(item.id) {
            $0.status = .preparing
            $0.errorMessage = nil
        }

        do {
            try await resolveAndStart(
                itemID: item.id,
                anime: item.anime,
                episodeID: item.episodeID,
                client: client
            )
        } catch is CancellationError {
            updateItem(item.id) {
                $0.status = .paused
                $0.errorMessage = nil
            }
        } catch {
            updateItem(item.id) {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
    }

    func pause(_ item: VideoDownloadItem) {
        guard item.status == .downloading else { return }
        progressThrottler.remove(item.id)
        updateItem(item.id) {
            $0.status = .paused
            $0.errorMessage = nil
        }
        Task {
            let task = await systemTask(for: item.id)
            task?.suspend()
        }
    }

    func resume(_ item: VideoDownloadItem) {
        guard item.status == .paused else { return }
        updateItem(item.id) {
            $0.status = .downloading
            $0.errorMessage = nil
        }
        Task {
            if let task = await systemTask(for: item.id) {
                task.resume()
            } else {
                updateItem(item.id) {
                    $0.status = .failed
                    $0.errorMessage = "下载任务已中断，请重试。"
                }
            }
        }
    }

    func remove(_ item: VideoDownloadItem) {
        progressThrottler.remove(item.id)
        let localURL = localURL(for: item)
        items.removeAll { $0.id == item.id }
        saveItems()

        Task {
            let task = await systemTask(for: item.id)
            task?.cancel()
        }
        if let localURL {
            Task(priority: .utility) {
                await fileStore.remove([localURL])
            }
        }
    }

    func clearCompleted() {
        let completed = items.filter { $0.status == .completed }
        guard !completed.isEmpty else { return }
        let localURLs = completed.compactMap {
            localURL(for: $0)
        }
        let completedIDs = Set(completed.map(\.id))
        items.removeAll { completedIDs.contains($0.id) }
        saveItems()
        Task(priority: .utility) {
            await fileStore.remove(localURLs)
        }
    }

    func item(
        platformID: AnimePlatformID,
        animeID: String,
        episodeID: String
    ) -> VideoDownloadItem? {
        item(
            withID: VideoDownloadItem.identifier(
                platformID: platformID,
                animeID: animeID,
                episodeID: episodeID
            )
        )
    }

    func localPlaybackURL(
        platformID: AnimePlatformID,
        animeID: String,
        episodeID: String
    ) -> URL? {
        guard let item = item(
            platformID: platformID,
            animeID: animeID,
            episodeID: episodeID
        ), item.status == .completed else {
            return nil
        }
        return localURL(for: item)
    }

    func isUnavailableForDownload(
        platformID: AnimePlatformID,
        animeID: String,
        episodeID: String
    ) -> Bool {
        guard let item = item(
            platformID: platformID,
            animeID: animeID,
            episodeID: episodeID
        ) else {
            return false
        }
        return [.preparing, .downloading, .paused, .completed]
            .contains(item.status)
    }

    private func startAssetDownload(
        for item: VideoDownloadItem,
        sourceURL: URL,
        allowsCellularAccess: Bool
    ) throws {
        let asset = AVURLAsset(
            url: sourceURL,
            options: [
                AVURLAssetAllowsCellularAccessKey: allowsCellularAccess
            ]
        )
        guard let task = assetSession.makeAssetDownloadTask(
            asset: asset,
            assetTitle: "\(item.anime.title) - \(item.episodeTitle)",
            assetArtworkData: nil,
            options: nil
        ) else {
            throw VideoDownloadError.unsupportedSource
        }
        task.taskDescription = item.id
        task.resume()
    }

    private func resolveAndStart(
        itemID: String,
        anime: Anime,
        episodeID: String,
        client: AnimeAPIClient
    ) async throws {
        let sourceURL = try await client.downloadPlaybackURL(
            anime: anime,
            episodeID: episodeID
        )
        try Task.checkCancellation()
        guard item(withID: itemID) != nil else { return }
        updateItem(itemID) {
            $0.status = .downloading
            $0.errorMessage = nil
        }
        guard let refreshed = item(withID: itemID) else { return }
        try startAssetDownload(
            for: refreshed,
            sourceURL: sourceURL,
            allowsCellularAccess: client.downloadOverCellular
        )
    }

    private func restoreSystemTasks() {
        assetSession.getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let restoredIDs = Set(tasks.compactMap(\.taskDescription))
                for task in tasks {
                    guard let id = task.taskDescription else { continue }
                    switch task.state {
                    case .running:
                        updateItem(id) { $0.status = .downloading }
                    case .suspended:
                        updateItem(id) { $0.status = .paused }
                    default:
                        break
                    }
                }

                for item in items where
                    [.preparing, .downloading, .paused].contains(item.status)
                        && !restoredIDs.contains(item.id) {
                    updateItem(item.id) {
                        $0.status = .failed
                        $0.errorMessage = "下载任务已中断，请重试。"
                    }
                }
            }
        }
    }

    private func validateCompletedItems() {
        for item in items where item.status == .completed {
            guard localURL(for: item) == nil else { continue }
            updateItem(item.id) {
                $0.status = .failed
                $0.localPath = nil
                $0.errorMessage = "本地文件已不存在，请重新下载。"
            }
        }
    }

    private func systemTask(for itemID: String) async -> URLSessionTask? {
        await withCheckedContinuation { continuation in
            assetSession.getAllTasks { tasks in
                continuation.resume(
                    returning: tasks.first {
                        $0.taskDescription == itemID
                    }
                )
            }
        }
    }

    private func item(withID id: String) -> VideoDownloadItem? {
        items.first { $0.id == id }
    }

    private func replaceOrInsert(_ item: VideoDownloadItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        sortItems()
        saveItems()
    }

    private func updateItem(
        _ id: String,
        update: (inout VideoDownloadItem) -> Void
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&items[index])
        items[index].updatedAt = Date()
        sortItems()
        saveItems()
    }

    private func updateProgress(_ updates: [String: Double]) {
        guard !updates.isEmpty else { return }
        var updatedItems = items
        let now = Date()
        var shouldPersist = false
        var didUpdate = false
        for (id, progress) in updates {
            guard let index = updatedItems.firstIndex(
                where: { $0.id == id }
            ), updatedItems[index].status == .downloading else {
                continue
            }
            updatedItems[index].status = .downloading
            updatedItems[index].progress = progress
            updatedItems[index].errorMessage = nil
            didUpdate = true

            if progress >= 1
                || now.timeIntervalSince(
                    lastProgressPersistenceDates[id] ?? .distantPast
                ) >= 1 {
                lastProgressPersistenceDates[id] = now
                shouldPersist = true
            }
        }
        guard didUpdate else { return }
        items = updatedItems
        if shouldPersist {
            saveItems()
        }
    }

    private func sortItems() {
        items.sort { $0.updatedAt > $1.updatedAt }
    }

    private func saveItems() {
        persistenceRevision += 1
        let revision = persistenceRevision
        let snapshot = items
        let persistence = persistence
        lastPersistenceTask = Task {
            await persistence.save(
                snapshot,
                forKey: Keys.items,
                revision: revision
            )
        }
    }

    private func localURL(for item: VideoDownloadItem) -> URL? {
        guard let path = item.localPath, !path.isEmpty else { return nil }
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(path)
        }
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private nonisolated static func persistedPath(for url: URL) -> String {
        let homePath = URL(fileURLWithPath: NSHomeDirectory())
            .standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return path }
        return String(path.dropFirst(homePath.count + 1))
    }

    private static func loadItems(
        defaults: UserDefaults
    ) -> [VideoDownloadItem] {
        guard let data = defaults.data(forKey: Keys.items),
              let items = try? JSONDecoder().decode(
                  [VideoDownloadItem].self,
                  from: data
              ) else {
            return []
        }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    private lazy var assetSession: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.backgroundSessionIdentifier
        )
        configuration.allowsCellularAccess = true
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: delegateQueue
        )
    }()

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let fileStore: DownloadFileStore
    private let persistence: VideoDownloadPersistence
    nonisolated private let progressThrottler: DownloadProgressThrottler
    nonisolated private let delegateEventSequencer =
        DownloadDelegateEventSequencer()
    private var lastProgressPersistenceDates: [String: Date] = [:]
    private var persistenceRevision = 0
    private var lastPersistenceTask: Task<Void, Never>?
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "work.picav.video-downloads.delegate"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private static var backgroundEventsCompletionHandler: (() -> Void)?

    private enum Keys {
        static let items = "videoDownloads.items"
    }
}

extension VideoDownloadService: AVAssetDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let loadedDuration = loadedTimeRanges.reduce(0.0) {
            $0 + CMTimeGetSeconds($1.timeRangeValue.duration)
        }
        let expectedDuration = CMTimeGetSeconds(
            timeRangeExpectedToLoad.duration
        )
        guard loadedDuration.isFinite,
              expectedDuration.isFinite,
              expectedDuration > 0 else {
            return
        }
        let progress = min(max(loadedDuration / expectedDuration, 0), 1)
        progressThrottler.submit(progress, for: id)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
        progressThrottler.remove(id)
        let path = Self.persistedPath(for: location)
        delegateEventSequencer.enqueue { [weak self] in
            await MainActor.run { [weak self] in
                self?.updateItem(id) {
                    $0.localPath = path
                    $0.progress = 1
                    $0.status = .completed
                    $0.errorMessage = nil
                }
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = task.taskDescription, let error else { return }
        progressThrottler.remove(id)
        let errorMessage = error.localizedDescription
        delegateEventSequencer.enqueue { [weak self] in
            await MainActor.run { [weak self] in
                guard let self,
                      let item = item(withID: id),
                      item.status != .completed else {
                    return
                }
                updateItem(id) {
                    $0.status = .failed
                    $0.errorMessage = errorMessage
                }
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {
        delegateEventSequencer.enqueue { [weak self] in
            let persistenceTask = await MainActor.run { [weak self] in
                self?.lastPersistenceTask
            }
            await persistenceTask?.value
            await MainActor.run {
                let completionHandler =
                    Self.backgroundEventsCompletionHandler
                Self.backgroundEventsCompletionHandler = nil
                completionHandler?()
            }
        }
    }
}

private actor DownloadFileStore {
    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func remove(_ urls: [URL]) {
        for url in urls {
            guard !Task.isCancelled else { return }
            try? fileManager.removeItem(at: url)
        }
    }

    private let fileManager: FileManager
}

private actor VideoDownloadPersistence {
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func save(
        _ items: [VideoDownloadItem],
        forKey key: String,
        revision: Int
    ) {
        guard revision >= latestRevision,
              let data = try? JSONEncoder().encode(items) else {
            return
        }
        latestRevision = revision
        defaults.set(data, forKey: key)
    }

    private let defaults: UserDefaults
    private var latestRevision = 0
}

private final class DownloadDelegateEventSequencer: @unchecked Sendable {
    @discardableResult
    func enqueue(
        _ operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        lock.lock()
        let predecessor = tail
        let task = Task {
            await predecessor?.value
            await operation()
        }
        tail = task
        lock.unlock()
        return task
    }

    private let lock = NSLock()
    private var tail: Task<Void, Never>?
}

private final class DownloadProgressThrottler: @unchecked Sendable {
    init(
        interval: TimeInterval = 0.2
    ) {
        self.interval = interval
    }

    func setOnFlush(
        _ onFlush: @escaping ([String: Double]) -> Void
    ) {
        lock.lock()
        self.onFlush = onFlush
        lock.unlock()
    }

    func submit(_ progress: Double, for id: String) {
        lock.lock()
        pending[id] = progress
        let shouldSchedule = !isFlushScheduled
        if shouldSchedule {
            isFlushScheduled = true
        }
        lock.unlock()

        guard shouldSchedule else { return }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.flush()
        }
    }

    func remove(_ id: String) {
        lock.lock()
        pending[id] = nil
        lock.unlock()
    }

    private func flush() {
        lock.lock()
        let updates = pending
        pending.removeAll(keepingCapacity: true)
        isFlushScheduled = false
        let onFlush = self.onFlush
        lock.unlock()
        guard !updates.isEmpty, let onFlush else { return }
        onFlush(updates)
    }

    private let interval: TimeInterval
    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "work.picav.video-downloads.progress",
        qos: .utility
    )
    private var pending: [String: Double] = [:]
    private var isFlushScheduled = false
    private var onFlush: (([String: Double]) -> Void)?
}

private enum VideoDownloadError: LocalizedError {
    case unsupportedSource

    var errorDescription: String? {
        "当前播放源不支持本地下载。"
    }
}
