import Combine
import Foundation

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var categories: [AnimeCategory] = []
    @Published private(set) var items: [Anime] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreErrorMessage: String?
    @Published private(set) var selectedCategoryID: String?
    @Published private(set) var sort: AnimeSort

    init(
        client: AnimeAPIClient,
        sort: AnimeSort = .popular,
        requiresCategory: Bool = false
    ) {
        self.client = client
        self.sort = sort
        self.requiresCategory = requiresCategory
    }

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }
        let requestID = UUID()
        activeRequestID = requestID
        invalidateLoadMore()
        state = .loading
        do {
            if categories.isEmpty {
                let loadedCategories = try await client.fetchCategories()
                guard isCurrent(requestID) else { return }
                categories = loadedCategories.stableUniqued(id: \.id)
            }
            if requiresCategory, selectedCategoryID == nil {
                selectedCategoryID = categories.first?.id
            }
            guard !requiresCategory || selectedCategoryID != nil else {
                items = []
                hasMore = false
                state = .loaded
                return
            }
            try await loadFirstPage(requestID: requestID)
        } catch is CancellationError {
            restoreStateAfterCancellation(requestID)
        } catch {
            guard isCurrent(requestID) else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func selectCategory(_ id: String?) {
        guard selectedCategoryID != id else { return }
        selectedCategoryID = id
        scheduleReload()
    }

    func selectSort(_ value: AnimeSort) {
        guard sort != value else { return }
        sort = value
        scheduleReload()
    }

    func reloadResults() async {
        let requestID = UUID()
        activeRequestID = requestID
        invalidateLoadMore()
        state = .loading
        do {
            try await loadFirstPage(requestID: requestID)
        } catch is CancellationError {
            restoreStateAfterCancellation(requestID)
        } catch {
            guard isCurrent(requestID) else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current item: Anime) async {
        guard state == .loaded,
              item.id == items.last?.id,
              hasMore,
              !isLoadingMore else {
            return
        }
        let requestID = UUID()
        activeLoadMoreRequestID = requestID
        let requestedCategoryID = selectedCategoryID
        let requestedSort = sort
        let nextPage = page + 1
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer {
            if activeLoadMoreRequestID == requestID {
                isLoadingMore = false
            }
        }

        do {
            let next = try await client.fetchAnime(
                categoryID: requestedCategoryID,
                page: nextPage,
                sort: requestedSort
            )
            guard !Task.isCancelled,
                  activeLoadMoreRequestID == requestID,
                  selectedCategoryID == requestedCategoryID,
                  sort == requestedSort else {
                return
            }
            items.append(
                contentsOf: next.items.stableUniqued(
                    seededBy: Set(items.map(\.id)),
                    id: \.id
                )
            )
            page = next.page
            hasMore = next.hasMore
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadMoreRequestID == requestID else { return }
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    func retryLoadMore() async {
        guard let item = items.last else { return }
        await loadMoreIfNeeded(current: item)
    }

    private func loadFirstPage(requestID: UUID) async throws {
        let requestedCategoryID = selectedCategoryID
        let requestedSort = sort
        let first = try await client.fetchAnime(
            categoryID: requestedCategoryID,
            page: 1,
            sort: requestedSort
        )
        guard !Task.isCancelled,
              isCurrent(requestID),
              selectedCategoryID == requestedCategoryID,
              sort == requestedSort else {
            return
        }
        items = first.items.stableUniqued(id: \.id)
        page = 1
        hasMore = first.hasMore
        loadMoreErrorMessage = nil
        state = .loaded
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await self?.reloadResults()
        }
    }

    private func invalidateLoadMore() {
        activeLoadMoreRequestID = nil
        isLoadingMore = false
        loadMoreErrorMessage = nil
    }

    private func isCurrent(_ requestID: UUID) -> Bool {
        !Task.isCancelled && activeRequestID == requestID
    }

    private func restoreStateAfterCancellation(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        state = items.isEmpty ? .idle : .loaded
    }

    private let client: AnimeAPIClient
    private let requiresCategory: Bool
    private var page = 1
    private var activeRequestID: UUID?
    private var activeLoadMoreRequestID: UUID?
    private var reloadTask: Task<Void, Never>?
}
