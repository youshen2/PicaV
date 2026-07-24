import CryptoKit
import Foundation

enum AnimeDetailCacheService {
    static let defaultMaxDiskSizeMB = 50

    @MainActor
    @discardableResult
    static func configure(defaults: UserDefaults = .standard) -> Task<Void, Never> {
        if defaults.object(forKey: AnimeCacheSettingsKey.detailIsEnabled) == nil {
            defaults.set(true, forKey: AnimeCacheSettingsKey.detailIsEnabled)
        }
        if defaults.object(forKey: AnimeCacheSettingsKey.detailMaxDiskSizeMB) == nil {
            defaults.set(
                defaultMaxDiskSizeMB,
                forKey: AnimeCacheSettingsKey.detailMaxDiskSizeMB
            )
        }

        let storedSize = defaults.integer(
            forKey: AnimeCacheSettingsKey.detailMaxDiskSizeMB
        )
        withLock {
            diskCapacityBytes = max(storedSize, minimumDiskSizeMB) * 1_024 * 1_024
            prepareDirectory()
        }

        activeTrimTask?.cancel()
        let task = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return }
            withLock {
                trimIfNeeded()
            }
        }
        activeTrimTask = task
        return task
    }

    @MainActor
    static func clear() async {
        activeTrimTask?.cancel()
        await Task.detached(priority: .utility) {
            withLock {
                try? FileManager.default.removeItem(at: directoryURL)
                prepareDirectory()
            }
        }.value
    }

    static func usage() async -> AnimeCacheUsage {
        await Task.detached(priority: .utility) {
            withLock {
                AnimeCacheUsage(
                    diskBytes: Int(min(diskUsage(), Int64(Int.max)))
                )
            }
        }.value
    }

    static func detail(
        videoID: String,
        platformID: AnimePlatformID,
        scope: String
    ) async -> AnimeDetail? {
        guard isEnabled else { return nil }
        return await Task.detached(priority: .utility) {
            withLock {
                let fileURL = cacheFileURL(
                    videoID: videoID,
                    platformID: platformID,
                    scope: scope
                )
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return nil
                }
                guard let data = try? Data(contentsOf: fileURL),
                      let payload = try? JSONDecoder().decode(
                          CachedDetail.self,
                          from: data
                      ),
                      payload.version == cacheFormatVersion,
                      isValid(payload.detail) else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return nil
                }
                touch(fileURL)
                return payload.detail
            }
        }.value
    }

    static func store(
        _ detail: AnimeDetail,
        videoID: String,
        platformID: AnimePlatformID,
        scope: String
    ) async {
        guard isEnabled, isValid(detail) else { return }
        let cachedDetail = metadataOnly(detail)
        guard let data = try? JSONEncoder().encode(
            CachedDetail(
                version: cacheFormatVersion,
                cachedAt: Date(),
                detail: cachedDetail
            )
        ) else {
            return
        }

        await Task.detached(priority: .utility) {
            let shouldTrim = withLock {
                prepareDirectory()
                let fileURL = cacheFileURL(
                    videoID: videoID,
                    platformID: platformID,
                    scope: scope
                )
                do {
                    try data.write(to: fileURL, options: [.atomic])
                    touch(fileURL)
                } catch {
                    return false
                }
                guard !isTrimScheduled else { return false }
                isTrimScheduled = true
                return true
            }
            if shouldTrim {
                scheduleTrim()
            }
        }.value
    }

    private static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: AnimeCacheSettingsKey.detailIsEnabled) == nil
            ? true
            : defaults.bool(forKey: AnimeCacheSettingsKey.detailIsEnabled)
    }

    private static func isValid(_ detail: AnimeDetail) -> Bool {
        let id = detail.anime.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = detail.anime.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              !title.isEmpty,
              !id.hasPrefix("preview-"),
              validRemoteURL(detail.anime.coverURL),
              validRemoteURL(detail.anime.bannerURL) else {
            return false
        }

        let synopsis = detail.synopsis.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return synopsis != "暂无剧情简介"
            || !detail.anime.tags.isEmpty
            || detail.releaseDate?.isEmpty == false
            || detail.anime.watchCount > 0
            || detail.anime.likeCount > 0
            || detail.episodes.count > 1
    }

    private static func validRemoteURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && url.host?.isEmpty == false
    }

    private static func metadataOnly(_ detail: AnimeDetail) -> AnimeDetail {
        AnimeDetail(
            anime: detail.anime,
            synopsis: detail.synopsis,
            episodes: [],
            currentEpisodeID: detail.currentEpisodeID,
            videoPath: nil,
            authKey: nil,
            cdnID: nil,
            canWatch: false,
            releaseDate: detail.releaseDate,
            isFavorite: detail.isFavorite,
            uploader: detail.uploader
        )
    }

    private static func scheduleTrim() {
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            withLock {
                defer { isTrimScheduled = false }
                trimIfNeeded()
            }
        }
    }

    private static var directoryURL: URL {
        let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("AnimeDetailCache", isDirectory: true)
    }

    private static func cacheFileURL(
        videoID: String,
        platformID: AnimePlatformID,
        scope: String
    ) -> URL {
        let key = [platformID.rawValue, scope, videoID].joined(separator: "|")
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent(
            "\(digest).json",
            isDirectory: false
        )
    }

    private static func prepareDirectory() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private static func touch(_ fileURL: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    private static func trimIfNeeded() {
        guard !Task.isCancelled else { return }
        let files = cacheFiles()
        var totalBytes = files.reduce(Int64(0)) { $0 + $1.byteCount }
        guard totalBytes > Int64(diskCapacityBytes) else { return }

        for file in files.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            guard !Task.isCancelled else { return }
            try? FileManager.default.removeItem(at: file.url)
            totalBytes -= file.byteCount
            if totalBytes <= Int64(diskCapacityBytes) {
                break
            }
        }
    }

    private static func diskUsage() -> Int64 {
        cacheFiles().reduce(Int64(0)) { $0 + $1.byteCount }
    }

    private static func cacheFiles() -> [CacheFile] {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return nil
            }
            return CacheFile(
                url: url,
                byteCount: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private struct CachedDetail: Codable {
        let version: Int
        let cachedAt: Date
        let detail: AnimeDetail
    }

    private struct CacheFile {
        let url: URL
        let byteCount: Int64
        let modifiedAt: Date
    }

    private static let minimumDiskSizeMB = 5
    private static let cacheFormatVersion = 1
    private static let lock = NSLock()
    private static var diskCapacityBytes = defaultMaxDiskSizeMB * 1_024 * 1_024
    private static var isTrimScheduled = false
    private static var activeTrimTask: Task<Void, Never>?
}
