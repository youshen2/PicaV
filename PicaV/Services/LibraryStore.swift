import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [Anime]
    @Published private(set) var history: [WatchHistoryEntry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedFavorites = Self.decode(
            [Anime].self,
            from: defaults.data(forKey: Keys.favorites)
        ) ?? []
        let loadedHistory = Self.decode(
            [WatchHistoryEntry].self,
            from: defaults.data(forKey: Keys.history)
        ) ?? []
        favorites = loadedFavorites
        history = loadedHistory.map { entry in
            guard entry.anime.coverURL == nil || entry.anime.bannerURL == nil,
                  let favorite = loadedFavorites.first(where: {
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
        if history != loadedHistory {
            defaults.set(
                try? JSONEncoder().encode(history),
                forKey: Keys.history
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
        defaults.set(try? JSONEncoder().encode(favorites), forKey: Keys.favorites)
    }

    private func saveHistory() {
        defaults.set(try? JSONEncoder().encode(history), forKey: Keys.history)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private let defaults: UserDefaults
    private var refreshingArtworkPlatforms = Set<AnimePlatformID>()
    private var refreshedArtworkPlatforms = Set<AnimePlatformID>()

    private enum Keys {
        static let favorites = "library.favorites"
        static let history = "library.history"
    }
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
