import Foundation

enum AnimeDetailCacheService {
    static let defaultMaxDiskSizeMB = 50

    @MainActor
    @discardableResult
    static func configure(
        defaults: UserDefaults = .standard
    ) -> Task<Void, Never> {
        if defaults.object(
            forKey: AnimeCacheSettingsKey.detailIsEnabled
        ) == nil {
            defaults.set(
                true,
                forKey: AnimeCacheSettingsKey.detailIsEnabled
            )
        }
        if defaults.object(
            forKey: AnimeCacheSettingsKey.detailMaxDiskSizeMB
        ) == nil {
            defaults.set(
                defaultMaxDiskSizeMB,
                forKey: AnimeCacheSettingsKey.detailMaxDiskSizeMB
            )
        }
        let storedSize = defaults.integer(
            forKey: AnimeCacheSettingsKey.detailMaxDiskSizeMB
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

    static func detail(
        videoID: String,
        platformID: AnimePlatformID,
        scope: String
    ) async -> AnimeDetail? {
        guard isEnabled, !Task.isCancelled else { return nil }
        let payload: CachedDetail? = await backend.value(
            forKey: cacheKey(
                videoID: videoID,
                platformID: platformID,
                scope: scope
            ),
            as: CachedDetail.self
        ) {
            $0.version == cacheFormatVersion && isValid($0.detail)
        }
        guard !Task.isCancelled else { return nil }
        return payload?.detail
    }

    static func store(
        _ detail: AnimeDetail,
        videoID: String,
        platformID: AnimePlatformID,
        scope: String
    ) async {
        guard isEnabled, isValid(detail), !Task.isCancelled else {
            return
        }
        let payload = CachedDetail(
            version: cacheFormatVersion,
            cachedAt: Date(),
            detail: metadataOnly(detail)
        )
        await backend.store(
            payload,
            forKey: cacheKey(
                videoID: videoID,
                platformID: platformID,
                scope: scope
            )
        )
    }

    private static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(
            forKey: AnimeCacheSettingsKey.detailIsEnabled
        ) == nil
            ? true
            : defaults.bool(
                forKey: AnimeCacheSettingsKey.detailIsEnabled
            )
    }

    private static func isValid(_ detail: AnimeDetail) -> Bool {
        let id = detail.anime.id.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let title = detail.anime.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
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
        return ["http", "https"].contains(
            url.scheme?.lowercased() ?? ""
        ) && url.host?.isEmpty == false
    }

    private static func metadataOnly(
        _ detail: AnimeDetail
    ) -> AnimeDetail {
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

    private static func cacheKey(
        videoID: String,
        platformID: AnimePlatformID,
        scope: String
    ) -> String {
        [platformID.rawValue, scope, videoID].joined(separator: "|")
    }

    private struct CachedDetail: Codable {
        let version: Int
        let cachedAt: Date
        let detail: AnimeDetail
    }

    private static let minimumDiskSizeMB = 5
    private static let cacheFormatVersion = 1
    private static let backend = DiskCacheBackend(
        directoryName: "AnimeDetailCache",
        fileExtension: "json",
        minimumCapacityBytes: minimumDiskSizeMB * 1_024 * 1_024,
        initialCapacityBytes: defaultMaxDiskSizeMB * 1_024 * 1_024
    )
    @MainActor private static var configurationGeneration = 0
}
