import CryptoKit
import Foundation
import ImageIO

struct AnimeCacheUsage: Equatable {
    let diskBytes: Int
}

enum AnimeCacheSettingsKey {
    static let imageMaxDiskSizeMB = "cache.images.maxDiskSizeMB"
    static let detailIsEnabled = "cache.details.isEnabled"
    static let detailMaxDiskSizeMB = "cache.details.maxDiskSizeMB"
}

enum AnimeImageCacheService {
    static let defaultMaxDiskSizeMB = 400

    @MainActor
    @discardableResult
    static func configure(defaults: UserDefaults = .standard) -> Task<Void, Never> {
        if defaults.object(forKey: AnimeCacheSettingsKey.imageMaxDiskSizeMB) == nil {
            defaults.set(
                defaultMaxDiskSizeMB,
                forKey: AnimeCacheSettingsKey.imageMaxDiskSizeMB
            )
        }

        let storedSize = defaults.integer(
            forKey: AnimeCacheSettingsKey.imageMaxDiskSizeMB
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

    static func cachedData(forKey key: String) async -> Data? {
        await Task.detached(priority: .utility) {
            withLock {
                let fileURL = cacheFileURL(forKey: key)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return nil
                }
                guard let data = try? Data(contentsOf: fileURL),
                      isDecodable(data) else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return nil
                }
                touch(fileURL)
                return data
            }
        }.value
    }

    static func store(_ data: Data, forKey key: String) async {
        guard isDecodable(data) else { return }
        await Task.detached(priority: .utility) {
            let shouldTrim = withLock {
                prepareDirectory()
                let fileURL = cacheFileURL(forKey: key)
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

    static func remove(forKey key: String) {
        withLock {
            try? FileManager.default.removeItem(at: cacheFileURL(forKey: key))
        }
    }

    static func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
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

    private static func isDecodable(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    private static var directoryURL: URL {
        let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("AnimeImageCache", isDirectory: true)
    }

    private static func cacheFileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent(digest, isDirectory: false)
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

    private struct CacheFile {
        let url: URL
        let byteCount: Int64
        let modifiedAt: Date
    }

    private static let minimumDiskSizeMB = 50
    private static let lock = NSLock()
    private static var diskCapacityBytes = defaultMaxDiskSizeMB * 1_024 * 1_024
    private static var isTrimScheduled = false
    private static var activeTrimTask: Task<Void, Never>?
}
