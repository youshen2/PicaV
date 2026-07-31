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
    static func configure(
        defaults: UserDefaults = .standard
    ) -> Task<Void, Never> {
        if defaults.object(
            forKey: AnimeCacheSettingsKey.imageMaxDiskSizeMB
        ) == nil {
            defaults.set(
                defaultMaxDiskSizeMB,
                forKey: AnimeCacheSettingsKey.imageMaxDiskSizeMB
            )
        }
        let storedSize = defaults.integer(
            forKey: AnimeCacheSettingsKey.imageMaxDiskSizeMB
        )
        configurationGeneration += 1
        let generation = configurationGeneration
        return Task(priority: .utility) {
            await backend.configure(
                capacityBytes: max(storedSize, minimumDiskSizeMB)
                    * 1_024 * 1_024,
                generation: generation
            )
        }
    }

    static func clear() async {
        await backend.clear()
    }

    static func usage() async -> AnimeCacheUsage {
        AnimeCacheUsage(diskBytes: await backend.usageBytes())
    }

    static func cachedData(forKey key: String) async -> Data? {
        guard !Task.isCancelled else { return nil }
        let data = await backend.data(
            forKey: key,
            validator: isDecodable
        )
        guard !Task.isCancelled else { return nil }
        return data
    }

    static func store(_ data: Data, forKey key: String) async {
        guard !Task.isCancelled else { return }
        await backend.store(
            data,
            forKey: key,
            validator: isDecodable
        )
    }

    static func remove(forKey key: String) async {
        await backend.remove(forKey: key)
    }

    static func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func isDecodable(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  nil
              ) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    private static let minimumDiskSizeMB = 50
    private static let backend = DiskCacheBackend(
        directoryName: "AnimeImageCache",
        minimumCapacityBytes: minimumDiskSizeMB * 1_024 * 1_024,
        initialCapacityBytes: defaultMaxDiskSizeMB * 1_024 * 1_024
    )
    @MainActor private static var configurationGeneration = 0
}
