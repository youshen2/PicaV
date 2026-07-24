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
        guard state != .loading else { return }

        state = .loading
        do {
            let result = try await client.fetchHomeSectionMore(
                section: section,
                page: 1,
                pageSize: pageSize,
                sortType: sort.rawValue
            )
            guard !Task.isCancelled else { return }
            items = result.items
            currentPage = 1
            hasMore = result.hasMore
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(currentItem: Anime) async {
        guard currentItem.id == items.last?.id,
              hasMore,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await client.fetchHomeSectionMore(
                section: section,
                page: currentPage + 1,
                pageSize: pageSize,
                sortType: sort.rawValue
            )
            guard !Task.isCancelled else { return }
            var knownIDs = Set(items.map(\.id))
            items.append(
                contentsOf: result.items.filter {
                    knownIDs.insert($0.id).inserted
                }
            )
            currentPage = result.page
            hasMore = result.hasMore
        } catch {
            hasMore = false
        }
    }

    private let section: AnimeHomeSection
    private let client: AnimeAPIClient
    private let pageSize = 20
    private var currentPage = 1
}
