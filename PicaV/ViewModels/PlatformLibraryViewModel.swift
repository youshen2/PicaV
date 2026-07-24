import Combine
import Foundation

enum LibrarySection: String, CaseIterable, Identifiable {
    case favorites
    case history

    var id: String { rawValue }
    var title: String { self == .favorites ? "收藏" : "历史" }
    var navigationTitle: String {
        self == .favorites ? "我的收藏" : "浏览记录"
    }
}

@MainActor
final class PlatformLibraryViewModel: ObservableObject {
    @Published private(set) var favoriteState: LoadState = .idle
    @Published private(set) var historyState: LoadState = .idle
    @Published private(set) var favorites: [Anime] = []
    @Published private(set) var history: [Anime] = []

    init(client: AnimeAPIClient) {
        self.client = client
    }

    func state(for section: LibrarySection) -> LoadState {
        section == .favorites ? favoriteState : historyState
    }

    func items(for section: LibrarySection) -> [Anime] {
        section == .favorites ? favorites : history
    }

    func load(
        _ section: LibrarySection,
        force: Bool = false
    ) async {
        guard state(for: section) != .loading else { return }
        if !force, state(for: section) == .loaded { return }

        setState(.loading, for: section)
        do {
            let page = try await fetch(section, page: 1)
            guard !Task.isCancelled else { return }
            setItems(page.items, for: section)
            setPage(1, hasMore: page.hasMore, for: section)
            setState(.loaded, for: section)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            setState(.failed(error.localizedDescription), for: section)
        }
    }

    func loadMoreIfNeeded(
        _ section: LibrarySection,
        currentItem: Anime
    ) async {
        let items = items(for: section)
        guard currentItem.id == items.last?.id,
              hasMore(for: section),
              !isLoadingMore(for: section) else {
            return
        }

        setIsLoadingMore(true, for: section)
        defer { setIsLoadingMore(false, for: section) }
        do {
            let nextPage = page(for: section) + 1
            let result = try await fetch(section, page: nextPage)
            guard !Task.isCancelled else { return }
            appendUnique(result.items, for: section)
            setPage(nextPage, hasMore: result.hasMore, for: section)
        } catch {
            return
        }
    }

    func reset() {
        favoriteState = .idle
        historyState = .idle
        favorites = []
        history = []
        favoritePage = 0
        historyPage = 0
        favoriteHasMore = false
        historyHasMore = false
    }

    private func fetch(
        _ section: LibrarySection,
        page: Int
    ) async throws -> AnimePage {
        switch section {
        case .favorites:
            return try await client.fetchPlatformFavorites(
                page: page,
                pageSize: pageSize
            )
        case .history:
            return try await client.fetchPlatformHistory(
                page: page,
                pageSize: pageSize
            )
        }
    }

    private func setState(_ state: LoadState, for section: LibrarySection) {
        switch section {
        case .favorites: favoriteState = state
        case .history: historyState = state
        }
    }

    private func setItems(_ items: [Anime], for section: LibrarySection) {
        switch section {
        case .favorites: favorites = items
        case .history: history = items
        }
    }

    private func appendUnique(
        _ newItems: [Anime],
        for section: LibrarySection
    ) {
        var knownIDs = Set(items(for: section).map(\.id))
        let uniqueItems = newItems.filter { knownIDs.insert($0.id).inserted }
        switch section {
        case .favorites: favorites.append(contentsOf: uniqueItems)
        case .history: history.append(contentsOf: uniqueItems)
        }
    }

    private func page(for section: LibrarySection) -> Int {
        section == .favorites ? favoritePage : historyPage
    }

    private func hasMore(for section: LibrarySection) -> Bool {
        section == .favorites ? favoriteHasMore : historyHasMore
    }

    private func isLoadingMore(for section: LibrarySection) -> Bool {
        section == .favorites
            ? isLoadingMoreFavorites
            : isLoadingMoreHistory
    }

    private func setPage(
        _ page: Int,
        hasMore: Bool,
        for section: LibrarySection
    ) {
        switch section {
        case .favorites:
            favoritePage = page
            favoriteHasMore = hasMore
        case .history:
            historyPage = page
            historyHasMore = hasMore
        }
    }

    private func setIsLoadingMore(
        _ isLoading: Bool,
        for section: LibrarySection
    ) {
        switch section {
        case .favorites: isLoadingMoreFavorites = isLoading
        case .history: isLoadingMoreHistory = isLoading
        }
    }

    private let client: AnimeAPIClient
    private let pageSize = 50
    private var favoritePage = 0
    private var historyPage = 0
    private var favoriteHasMore = false
    private var historyHasMore = false
    private var isLoadingMoreFavorites = false
    private var isLoadingMoreHistory = false
}
