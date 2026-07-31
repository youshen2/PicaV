import Combine
import Foundation

enum HomeSectionSort: Int, CaseIterable, Identifiable {
    case all = 0
    case latest = 1
    case popular = 2
    case mostLiked = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .latest: return "最新上传"
        case .popular: return "最多观看"
        case .mostLiked: return "最多点赞"
        }
    }
}

@MainActor
final class HomeSectionMoreViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var items: [Anime] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreErrorMessage: String?
    @Published private(set) var sort: HomeSectionSort

    init(section: AnimeHomeSection, client: AnimeAPIClient) {
        self.section = section
        self.client = client
        sort = HomeSectionSort(
            rawValue: section.actions?.sortType ?? 0
        ) ?? .all
    }

    func selectSort(_ sort: HomeSectionSort) {
        guard sort != self.sort else { return }
        self.sort = sort
    }

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }

        let requestID = UUID()
        activeLoadRequestID = requestID
        invalidateLoadMore()
        let requestedSort = sort
        state = .loading
        do {
            let result = try await client.fetchHomeSectionMore(
                section: section,
                page: 1,
                pageSize: pageSize,
                sortType: requestedSort.rawValue
            )
            guard !Task.isCancelled,
                  activeLoadRequestID == requestID,
                  sort == requestedSort else {
                restoreStateAfterCancellation(requestID: requestID)
                return
            }
            items = result.items.stableUniqued(id: \.id)
            currentPage = 1
            hasMore = result.hasMore
            loadMoreErrorMessage = nil
            state = .loaded
        } catch is CancellationError {
            restoreStateAfterCancellation(requestID: requestID)
        } catch {
            guard !Task.isCancelled,
                  activeLoadRequestID == requestID else {
                restoreStateAfterCancellation(requestID: requestID)
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(currentItem: Anime) async {
        guard state == .loaded,
              currentItem.id == items.last?.id,
              hasMore,
              !isLoadingMore else {
            return
        }

        let requestID = UUID()
        activeLoadMoreRequestID = requestID
        let requestedSort = sort
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer {
            if activeLoadMoreRequestID == requestID {
                isLoadingMore = false
            }
        }
        do {
            let result = try await client.fetchHomeSectionMore(
                section: section,
                page: currentPage + 1,
                pageSize: pageSize,
                sortType: requestedSort.rawValue
            )
            guard !Task.isCancelled,
                  activeLoadMoreRequestID == requestID,
                  sort == requestedSort else {
                return
            }
            items.append(
                contentsOf: result.items.stableUniqued(
                    seededBy: Set(items.map(\.id)),
                    id: \.id
                )
            )
            currentPage = result.page
            hasMore = result.hasMore
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadMoreRequestID == requestID else { return }
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    func retryLoadMore() async {
        guard let item = items.last else { return }
        await loadMoreIfNeeded(currentItem: item)
    }

    private func restoreStateAfterCancellation(requestID: UUID) {
        guard activeLoadRequestID == requestID else { return }
        state = items.isEmpty ? .idle : .loaded
    }

    private func invalidateLoadMore() {
        activeLoadMoreRequestID = nil
        isLoadingMore = false
        loadMoreErrorMessage = nil
    }

    private let section: AnimeHomeSection
    private let client: AnimeAPIClient
    private let pageSize = 20
    private var currentPage = 1
    private var activeLoadRequestID: UUID?
    private var activeLoadMoreRequestID: UUID?
}
