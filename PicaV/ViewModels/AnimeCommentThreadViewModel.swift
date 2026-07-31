import Combine
import Foundation

@MainActor
final class AnimeCommentThreadViewModel: ObservableObject {
    @Published private(set) var state: LoadState
    @Published private(set) var replies: [AnimeComment]
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreErrorMessage: String?

    init(
        videoID: String,
        rootComment: AnimeComment,
        client: AnimeAPIClient
    ) {
        self.videoID = videoID
        self.rootComment = rootComment
        self.client = client
        replies = rootComment.replies
        state = rootComment.replies.isEmpty ? .idle : .loaded
    }

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }

        let requestID = UUID()
        loadRequestID = requestID
        loadMoreRequestID = nil
        isLoadingMore = false
        loadMoreErrorMessage = nil
        state = .loading

        defer {
            if loadRequestID == requestID {
                loadRequestID = nil
            }
        }

        do {
            let loaded = try await page(number: 1)
            guard loadRequestID == requestID else { return }
            replies = loaded.stableUniqued { $0.id }
            currentPage = 1
            hasMore = loaded.count >= pageSize
            state = .loaded
        } catch is CancellationError {
            guard loadRequestID == requestID else { return }
            state = replies.isEmpty ? .idle : .loaded
            return
        } catch {
            guard loadRequestID == requestID else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current reply: AnimeComment) async {
        guard state == .loaded,
              hasMore,
              !isLoadingMore,
              reply.id == replies.last?.id else {
            return
        }

        await loadMore()
    }

    func retryLoadMore() async {
        guard loadMoreErrorMessage != nil else { return }
        await loadMore()
    }

    private func loadMore() async {
        guard state == .loaded, hasMore, !isLoadingMore else { return }

        let requestID = UUID()
        loadMoreRequestID = requestID
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer {
            if loadMoreRequestID == requestID {
                isLoadingMore = false
                loadMoreRequestID = nil
            }
        }

        do {
            let nextPage = currentPage + 1
            let loaded = try await page(number: nextPage)
            guard loadMoreRequestID == requestID else { return }
            let existingIDs = Set(replies.map(\.id))
            replies.append(
                contentsOf: loaded.stableUniqued(
                    seededBy: existingIDs,
                    id: { $0.id }
                )
            )
            currentPage = nextPage
            hasMore = loaded.count >= pageSize
        } catch is CancellationError {
            return
        } catch {
            guard loadMoreRequestID == requestID else { return }
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    private func page(number: Int) async throws -> [AnimeComment] {
        try await client.fetchComments(
            videoID: videoID,
            page: number,
            pageSize: pageSize,
            parentID: rootComment.id
        )
        .filter { $0.id != rootComment.id }
    }

    private let videoID: String
    private let rootComment: AnimeComment
    private let client: AnimeAPIClient
    private let pageSize = 30
    private var currentPage = 0
    private var hasMore = true
    private var loadRequestID: UUID?
    private var loadMoreRequestID: UUID?
}
