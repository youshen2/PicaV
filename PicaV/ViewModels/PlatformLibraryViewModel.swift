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
    @Published private var loadMoreErrors: [LibrarySection: String] = [:]

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
        if !force, state(for: section) == .loaded { return }

        let requestID = UUID()
        activeLoadRequestIDs[section] = requestID
        invalidateLoadMore(section)
        setState(.loading, for: section)
        do {
            let page = try await fetch(section, page: 1)
            guard !Task.isCancelled,
                  activeLoadRequestIDs[section] == requestID else {
                restoreStateAfterCancellation(
                    section,
                    requestID: requestID
                )
                return
            }
            setItems(page.items.stableUniqued(id: \.id), for: section)
            setPage(1, hasMore: page.hasMore, for: section)
            loadMoreErrors[section] = nil
            setState(.loaded, for: section)
        } catch is CancellationError {
            restoreStateAfterCancellation(section, requestID: requestID)
        } catch {
            guard !Task.isCancelled,
                  activeLoadRequestIDs[section] == requestID else {
                restoreStateAfterCancellation(
                    section,
                    requestID: requestID
                )
                return
            }
            setState(.failed(error.localizedDescription), for: section)
        }
    }

    func loadMoreIfNeeded(
        _ section: LibrarySection,
        currentItem: Anime
    ) async {
        let items = items(for: section)
        guard state(for: section) == .loaded,
              currentItem.id == items.last?.id,
              hasMore(for: section),
              !isLoadingMore(for: section) else {
            return
        }

        let requestID = UUID()
        activeLoadMoreRequestIDs[section] = requestID
        setIsLoadingMore(true, for: section)
        loadMoreErrors[section] = nil
        defer {
            if activeLoadMoreRequestIDs[section] == requestID {
                setIsLoadingMore(false, for: section)
            }
        }
        do {
            let nextPage = page(for: section) + 1
            let result = try await fetch(section, page: nextPage)
            guard !Task.isCancelled,
                  activeLoadMoreRequestIDs[section] == requestID else {
                return
            }
            appendUnique(result.items, for: section)
            setPage(result.page, hasMore: result.hasMore, for: section)
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadMoreRequestIDs[section] == requestID else {
                return
            }
            loadMoreErrors[section] = error.localizedDescription
        }
    }

    func retryLoadMore(_ section: LibrarySection) async {
        guard let item = items(for: section).last else { return }
        await loadMoreIfNeeded(section, currentItem: item)
    }

    func loadMoreError(for section: LibrarySection) -> String? {
        loadMoreErrors[section]
    }

    func isLoadingMore(_ section: LibrarySection) -> Bool {
        isLoadingMore(for: section)
    }

    func reset() {
        activeLoadRequestIDs.removeAll()
        activeLoadMoreRequestIDs.removeAll()
        favoriteState = .idle
        historyState = .idle
        favorites = []
        history = []
        favoritePage = 0
        historyPage = 0
        favoriteHasMore = false
        historyHasMore = false
        isLoadingMoreFavorites = false
        isLoadingMoreHistory = false
        loadMoreErrors.removeAll()
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
        let uniqueItems = newItems.stableUniqued(
            seededBy: Set(items(for: section).map(\.id)),
            id: \.id
        )
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

    private func restoreStateAfterCancellation(
        _ section: LibrarySection,
        requestID: UUID
    ) {
        guard activeLoadRequestIDs[section] == requestID else { return }
        setState(items(for: section).isEmpty ? .idle : .loaded, for: section)
    }

    private func invalidateLoadMore(_ section: LibrarySection) {
        activeLoadMoreRequestIDs[section] = nil
        setIsLoadingMore(false, for: section)
        loadMoreErrors[section] = nil
    }

    private let client: AnimeAPIClient
    private let pageSize = 50
    private var favoritePage = 0
    private var historyPage = 0
    private var favoriteHasMore = false
    private var historyHasMore = false
    private var isLoadingMoreFavorites = false
    private var isLoadingMoreHistory = false
    private var activeLoadRequestIDs: [LibrarySection: UUID] = [:]
    private var activeLoadMoreRequestIDs: [LibrarySection: UUID] = [:]
}
