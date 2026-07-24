import Combine
import Foundation

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var categories: [AnimeCategory] = []
    @Published private(set) var items: [Anime] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published var selectedCategoryID: String?
    @Published var sort: AnimeSort

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
        state = .loading
        do {
            if categories.isEmpty {
                categories = try await client.fetchCategories()
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
            try await loadFirstPage()
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func selectCategory(_ id: String?) async {
        guard selectedCategoryID != id else { return }
        selectedCategoryID = id
        await reloadResults()
    }

    func selectSort(_ value: AnimeSort) async {
        guard sort != value else { return }
        sort = value
        await reloadResults()
    }

    func reloadResults() async {
        state = .loading
        do {
            try await loadFirstPage()
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current item: Anime) async {
        guard item.id == items.last?.id, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let next = try await client.fetchAnime(
                categoryID: selectedCategoryID,
                page: page + 1,
                sort: sort
            )
            let existing = Set(items.map(\.id))
            items.append(contentsOf: next.items.filter { !existing.contains($0.id) })
            page = next.page
            hasMore = next.hasMore
        } catch {
            hasMore = false
        }
    }

    private func loadFirstPage() async throws {
        let first = try await client.fetchAnime(
            categoryID: selectedCategoryID,
            page: 1,
            sort: sort
        )
        items = first.items
        page = 1
        hasMore = first.hasMore
        state = .loaded
    }

    private let client: AnimeAPIClient
    private let requiresCategory: Bool
    private var page = 1
}
