import Combine
import Foundation

@MainActor
final class VideoDownloadService: ObservableObject {
    @Published private(set) var items: [VideoDownloadItem]

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        proxyRuntime: AppProxyRuntime? = nil
    ) {
        self.defaults = defaults
        self.proxyRuntime = proxyRuntime
        fileStore = VideoDownloadFileStore(fileManager: fileManager)
        localFileResolver = VideoDownloadLocalFileResolver(
            fileManager: fileManager
        )
        persistence = VideoDownloadPersistence(defaults: defaults)
        progressThrottler = DownloadProgressThrottler()
        items = Self.loadItems(defaults: defaults)

        progressThrottler.setOnFlush { [weak self] updates in
            Task { @MainActor [weak self] in
                self?.updateProgress(updates)
            }
        }
        restorePersistedItems()
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
            pendingJobs.append(
                DownloadJob(item: item, client: client)
            )
            queuedCount += 1
        }
        startPendingJobsIfNeeded()
        return queuedCount
    }

    func retry(
        _ item: VideoDownloadItem,
        client: AnimeAPIClient
    ) async {
        guard item.status == .failed else { return }
        if let localURL = localURL(for: item) {
            Task(priority: .utility) {
                await fileStore.remove([localURL])
            }
        }
        updateItem(item.id) {
            $0.localPath = nil
            $0.progress = 0
            $0.status = .preparing
            $0.errorMessage = nil
        }
        guard let refreshed = self.item(withID: item.id) else { return }
        pendingJobs.removeAll { $0.item.id == item.id }
        pendingJobs.append(
            DownloadJob(item: refreshed, client: client)
        )
        startPendingJobsIfNeeded()
    }

    func pause(_ item: VideoDownloadItem) {
        guard item.status == .downloading,
              let worker = workers[item.id] else {
            return
        }
        worker.pause()
        updateItem(item.id) {
            $0.status = .paused
            $0.errorMessage = nil
        }
    }

    func resume(_ item: VideoDownloadItem) {
        guard item.status == .paused else { return }
        guard let worker = workers[item.id] else {
            updateItem(item.id) {
                $0.status = .failed
                $0.errorMessage = "下载任务已中断，请重试。"
            }
            return
        }
        worker.resume()
        updateItem(item.id) {
            $0.status = .downloading
            $0.errorMessage = nil
        }
    }

    func remove(_ item: VideoDownloadItem) {
        progressThrottler.remove(item.id)
        cancelJob(withID: item.id)
        let localURL = localURL(for: item)
        items.removeAll { $0.id == item.id }
        saveItems()

        if let localURL {
            Task(priority: .utility) {
                await fileStore.remove([localURL])
            }
        }
    }

    func clearCompleted() {
        let completed = items.filter { $0.status == .completed }
        guard !completed.isEmpty else { return }
        let localURLs = completed.compactMap { localURL(for: $0) }
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
        ) else {
            return nil
        }
        return localPlaybackURL(for: item)
    }

    func localPlaybackURL(for item: VideoDownloadItem) -> URL? {
        guard let currentItem = self.item(withID: item.id),
              currentItem.status == .completed else {
            return nil
        }
        guard let localURL = localURL(for: currentItem),
              localURL.pathExtension.lowercased() == "mp4" else {
            updateItem(currentItem.id) {
                $0.status = .failed
                $0.errorMessage = "本地 MP4 文件已不存在，请重新下载。"
            }
            return nil
        }
        return localURL
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

    private func startPendingJobsIfNeeded() {
        while activeJobIDs.count < Self.maximumConcurrentDownloads,
              !pendingJobs.isEmpty {
            let job = pendingJobs.removeFirst()
            guard item(withID: job.item.id) != nil else { continue }
            activeJobIDs.insert(job.item.id)
            jobTasks[job.item.id] = Task { [weak self] in
                await self?.prepareAndStart(job)
            }
        }
    }

    private func prepareAndStart(_ job: DownloadJob) async {
        do {
            try await VideoDownloadNetworkPolicy.validate(
                allowsCellular: job.client.downloadOverCellular
            )
            try Task.checkCancellation()
            let sourceURL = try await job.client.downloadPlaybackURL(
                anime: job.item.anime,
                episodeID: job.item.episodeID
            )
            try Task.checkCancellation()
            let proxyURL = try await proxyRuntime?
                .mediaProxyURLForCurrentRoute()
            let output = try await fileStore.prepareOutput(for: job.item)
            try Task.checkCancellation()
            guard item(withID: job.item.id) != nil else {
                await fileStore.remove([
                    output.temporaryURL,
                    output.destinationURL
                ])
                finishJob(withID: job.item.id)
                return
            }

            let id = job.item.id
            let worker = VideoMP4DownloadWorker(
                configuration: .init(
                    sourceURL: sourceURL,
                    temporaryURL: output.temporaryURL,
                    destinationURL: output.destinationURL,
                    proxyURL: proxyURL
                ),
                progress: { [weak self] progress in
                    self?.progressThrottler.submit(progress, for: id)
                },
                completion: { [weak self] result in
                    Task { @MainActor [weak self] in
                        await self?.handleCompletion(
                            result,
                            output: output,
                            itemID: id
                        )
                    }
                }
            )
            workers[id] = worker
            updateItem(id) {
                $0.status = .downloading
                $0.errorMessage = nil
            }
            worker.start()
        } catch is CancellationError {
            finishJob(withID: job.item.id)
        } catch {
            updateItem(job.item.id) {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
            finishJob(withID: job.item.id)
        }
    }

    private func handleCompletion(
        _ result: Result<URL, Error>,
        output: VideoDownloadOutput,
        itemID: String
    ) async {
        progressThrottler.remove(itemID)
        workers[itemID] = nil

        switch result {
        case .success(let url):
            guard item(withID: itemID) != nil else {
                await fileStore.remove([url])
                finishJob(withID: itemID)
                return
            }
            let path = VideoDownloadLocalFileResolver.persistedPath(
                for: url
            )
            updateItem(itemID) {
                $0.localPath = path
                $0.progress = 1
                $0.status = .completed
                $0.errorMessage = nil
            }
        case .failure(let error):
            await fileStore.remove([
                output.temporaryURL,
                output.destinationURL
            ])
            guard item(withID: itemID) != nil else {
                finishJob(withID: itemID)
                return
            }
            if error is CancellationError {
                updateItem(itemID) {
                    $0.status = .failed
                    $0.errorMessage = "下载任务已取消，请重试。"
                }
            } else {
                updateItem(itemID) {
                    $0.status = .failed
                    $0.errorMessage = error.localizedDescription
                }
            }
        }
        finishJob(withID: itemID)
    }

    private func cancelJob(withID id: String) {
        pendingJobs.removeAll { $0.item.id == id }
        jobTasks[id]?.cancel()
        workers[id]?.cancel()
        if activeJobIDs.contains(id), workers[id] == nil {
            finishJob(withID: id)
        }
    }

    private func finishJob(withID id: String) {
        workers[id] = nil
        jobTasks[id] = nil
        activeJobIDs.remove(id)
        startPendingJobsIfNeeded()
    }

    private func restorePersistedItems() {
        var didChange = false
        for index in items.indices {
            switch items[index].status {
            case .preparing, .downloading, .paused:
                items[index].status = .failed
                items[index].errorMessage = "下载任务已中断，请重试。"
                didChange = true
            case .completed:
                guard let localURL = localURL(for: items[index]) else {
                    items[index].status = .failed
                    items[index].errorMessage =
                        "本地 MP4 文件已不存在，请重新下载。"
                    didChange = true
                    continue
                }
                guard localURL.pathExtension.lowercased() == "mp4" else {
                    items[index].status = .failed
                    items[index].errorMessage =
                        "旧版离线包需要重新下载为 MP4。"
                    didChange = true
                    continue
                }
                let stablePath = VideoDownloadLocalFileResolver
                    .persistedPath(for: localURL)
                if items[index].localPath != stablePath {
                    items[index].localPath = stablePath
                    didChange = true
                }
            case .failed:
                break
            }
        }
        guard didChange else { return }
        sortItems()
        saveItems()
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
        return localFileResolver.existingURL(for: path)
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

    private struct DownloadJob {
        let item: VideoDownloadItem
        let client: AnimeAPIClient
    }

    private let defaults: UserDefaults
    private let fileStore: VideoDownloadFileStore
    private let localFileResolver: VideoDownloadLocalFileResolver
    private let persistence: VideoDownloadPersistence
    private weak var proxyRuntime: AppProxyRuntime?
    nonisolated private let progressThrottler: DownloadProgressThrottler
    private var pendingJobs = [DownloadJob]()
    private var activeJobIDs = Set<String>()
    private var jobTasks = [String: Task<Void, Never>]()
    private var workers = [String: VideoMP4DownloadWorker]()
    private var lastProgressPersistenceDates: [String: Date] = [:]
    private var persistenceRevision = 0
    private var lastPersistenceTask: Task<Void, Never>?
    private static let maximumConcurrentDownloads = 2

    private enum Keys {
        static let items = "videoDownloads.items"
    }
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

private final class DownloadProgressThrottler: @unchecked Sendable {
    init(interval: TimeInterval = 0.2) {
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
