import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [Anime]
    @Published private(set) var history: [WatchHistoryEntry]

    init(
        platformID: AnimePlatformID = AnimePlatformRegistry.defaultID,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        currentPlatformID = platformID
        persistence = LibraryPersistence(defaults: defaults)
        let loaded = Self.load(
            platformID: platformID,
            defaults: defaults
        )
        favorites = loaded.favorites
        history = Self.mergedHistory(
            loaded.history,
            favorites: loaded.favorites
        )
        if history != loaded.history {
            defaults.set(
                try? JSONEncoder().encode(history),
                forKey: Keys.history(for: platformID)
            )
        }
    }

    func selectPlatform(_ platformID: AnimePlatformID) {
        guard platformID != currentPlatformID else { return }
        currentPlatformID = platformID
        let loaded = Self.load(
            platformID: platformID,
            defaults: defaults
        )
        favorites = loaded.favorites
        history = Self.mergedHistory(
            loaded.history,
            favorites: loaded.favorites
        )
    }

    private static func mergedHistory(
        _ history: [WatchHistoryEntry],
        favorites: [Anime]
    ) -> [WatchHistoryEntry] {
        history.map { entry in
            guard entry.anime.coverURL == nil || entry.anime.bannerURL == nil,
                  let favorite = favorites.first(where: {
                      $0.id == entry.anime.id
                  }) else {
                return entry
            }
            return entry.replacingAnime(
                Self.mergedSnapshot(
                    newValue: entry.anime,
                    previousValue: favorite
                )
            )
        }
    }

    func isFavorite(_ animeID: String) -> Bool {
        favorites.contains { $0.id == animeID }
    }

    func toggleFavorite(_ anime: Anime) {
        setFavorite(anime, isFavorite: !isFavorite(anime.id))
    }

    func setFavorite(_ anime: Anime, isFavorite: Bool) {
        favorites.removeAll { $0.id == anime.id }
        if isFavorite {
            favorites.insert(anime, at: 0)
        }
        saveFavorites()
    }

    func record(
        anime: Anime,
        episodeID: String,
        episodeTitle: String,
        progress: Double,
        duration: Double
    ) {
        let previousAnime = history.first {
            $0.anime.id == anime.id && $0.episodeID == episodeID
        }?.anime ?? favorites.first { $0.id == anime.id }
        let snapshot = Self.mergedSnapshot(
            newValue: anime,
            previousValue: previousAnime
        )
        history.removeAll { $0.anime.id == anime.id && $0.episodeID == episodeID }
        history.insert(
            WatchHistoryEntry(
                anime: snapshot,
                episodeID: episodeID,
                episodeTitle: episodeTitle,
                progress: progress.isFinite ? max(progress, 0) : 0,
                duration: duration.isFinite ? max(duration, 0) : 0,
                updatedAt: Date()
            ),
            at: 0
        )
        history = Array(history.prefix(100))
        saveHistory()
    }

    func refreshHistoryArtwork(using client: AnimeAPIClient) async {
        let platformID = client.platformID
        guard !refreshedArtworkPlatforms.contains(platformID),
              !refreshingArtworkPlatforms.contains(platformID) else {
            return
        }
        let candidates = history.prefix(30).filter {
            $0.anime.coverURL == nil || $0.anime.bannerURL == nil
        }
        guard !candidates.isEmpty else {
            refreshedArtworkPlatforms.insert(platformID)
            return
        }

        refreshingArtworkPlatforms.insert(platformID)
        defer {
            refreshingArtworkPlatforms.remove(platformID)
            refreshedArtworkPlatforms.insert(platformID)
        }

        for candidate in candidates {
            guard !Task.isCancelled else { return }
            guard let detail = try? await client.fetchDetail(
                videoID: candidate.episodeID,
                fallbackAnime: candidate.anime
            ),
                  let index = history.firstIndex(where: {
                      $0.id == candidate.id
                  }) else {
                continue
            }
            let current = history[index]
            let refreshedAnime = Self.refreshedArtworkSnapshot(
                current: current.anime,
                fresh: detail.anime
            )
            guard refreshedAnime != current.anime else { continue }
            history[index] = current.replacingAnime(refreshedAnime)
            saveHistory()
        }
    }

    private static func mergedSnapshot(
        newValue: Anime,
        previousValue: Anime?
    ) -> Anime {
        guard let previousValue else { return newValue }
        return Anime(
            id: newValue.id,
            title: newValue.title,
            coverURL: newValue.coverURL ?? previousValue.coverURL,
            bannerURL: newValue.bannerURL ?? previousValue.bannerURL,
            tags: newValue.tags.isEmpty ? previousValue.tags : newValue.tags,
            watchCount: max(newValue.watchCount, previousValue.watchCount),
            likeCount: max(newValue.likeCount, previousValue.likeCount),
            episodeLabel: newValue.episodeLabel ?? previousValue.episodeLabel,
            isPremium: newValue.isPremium || previousValue.isPremium,
            contentKind: newValue.contentKind
        )
    }

    private static func refreshedArtworkSnapshot(
        current: Anime,
        fresh: Anime
    ) -> Anime {
        Anime(
            id: current.id,
            title: current.title,
            coverURL: fresh.coverURL ?? current.coverURL,
            bannerURL: fresh.bannerURL
                ?? fresh.coverURL
                ?? current.bannerURL
                ?? current.coverURL,
            tags: current.tags.isEmpty ? fresh.tags : current.tags,
            watchCount: max(current.watchCount, fresh.watchCount),
            likeCount: max(current.likeCount, fresh.likeCount),
            episodeLabel: current.episodeLabel ?? fresh.episodeLabel,
            isPremium: current.isPremium || fresh.isPremium,
            contentKind: fresh.contentKind
        )
    }

    func removeHistory(_ entry: WatchHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    func clearFavorites() {
        favorites = []
        saveFavorites()
    }

    private func saveFavorites() {
        persistenceRevision += 1
        let revision = persistenceRevision
        let values = favorites
        let key = Keys.favorites(for: currentPlatformID)
        Task {
            await persistence.save(
                values,
                forKey: key,
                revision: revision
            )
        }
    }

    private func saveHistory() {
        persistenceRevision += 1
        let revision = persistenceRevision
        let values = history
        let key = Keys.history(for: currentPlatformID)
        Task {
            await persistence.save(
                values,
                forKey: key,
                revision: revision
            )
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func load(
        platformID: AnimePlatformID,
        defaults: UserDefaults
    ) -> (
        favorites: [Anime],
        history: [WatchHistoryEntry]
    ) {
        let favoritesKey = Keys.favorites(for: platformID)
        let historyKey = Keys.history(for: platformID)
        let canMigrateLegacy = platformID == AnimePlatformRegistry.defaultID
        let favoritesData = defaults.data(forKey: favoritesKey)
            ?? (
                canMigrateLegacy
                    ? defaults.data(forKey: Keys.legacyFavorites)
                    : nil
            )
        let historyData = defaults.data(forKey: historyKey)
            ?? (
                canMigrateLegacy
                    ? defaults.data(forKey: Keys.legacyHistory)
                    : nil
            )
        let favorites = decode([Anime].self, from: favoritesData) ?? []
        let history = decode(
            [WatchHistoryEntry].self,
            from: historyData
        ) ?? []
        if defaults.data(forKey: favoritesKey) == nil,
           favoritesData != nil {
            defaults.set(favoritesData, forKey: favoritesKey)
        }
        if defaults.data(forKey: historyKey) == nil,
           historyData != nil {
            defaults.set(historyData, forKey: historyKey)
        }
        return (favorites, history)
    }

    private let defaults: UserDefaults
    private let persistence: LibraryPersistence
    private var currentPlatformID: AnimePlatformID
    private var persistenceRevision = 0
    private var refreshingArtworkPlatforms = Set<AnimePlatformID>()
    private var refreshedArtworkPlatforms = Set<AnimePlatformID>()

    private enum Keys {
        static let legacyFavorites = "library.favorites"
        static let legacyHistory = "library.history"

        static func favorites(for platformID: AnimePlatformID) -> String {
            "\(legacyFavorites).\(platformID.rawValue)"
        }

        static func history(for platformID: AnimePlatformID) -> String {
            "\(legacyHistory).\(platformID.rawValue)"
        }
    }
}

private actor LibraryPersistence {
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func save<Value: Encodable>(
        _ value: Value,
        forKey key: String,
        revision: Int
    ) {
        guard revision >= (latestRevisions[key] ?? 0),
              let data = try? JSONEncoder().encode(value) else {
            return
        }
        latestRevisions[key] = revision
        defaults.set(data, forKey: key)
    }

    private let defaults: UserDefaults
    private var latestRevisions: [String: Int] = [:]
}

private extension WatchHistoryEntry {
    func replacingAnime(_ anime: Anime) -> WatchHistoryEntry {
        WatchHistoryEntry(
            anime: anime,
            episodeID: episodeID,
            episodeTitle: episodeTitle,
            progress: progress,
            duration: duration,
            updatedAt: updatedAt
        )
    }
}
