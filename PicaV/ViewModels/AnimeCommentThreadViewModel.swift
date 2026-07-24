import Combine
import Foundation

@MainActor
final class AnimeCommentThreadViewModel: ObservableObject {
    @Published private(set) var state: LoadState
    @Published private(set) var replies: [AnimeComment]
    @Published private(set) var isLoadingMore = false

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
        if replies.isEmpty {
            state = .loading
        }
        do {
            let loaded = try await page(number: 1)
            replies = unique(loaded)
            currentPage = 1
            hasMore = loaded.count >= pageSize
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current reply: AnimeComment) async {
        guard hasMore,
              !isLoadingMore,
              reply.id == replies.last?.id else {
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let nextPage = currentPage + 1
            let loaded = try await page(number: nextPage)
            replies = unique(replies + loaded)
            currentPage = nextPage
            hasMore = loaded.count >= pageSize
        } catch is CancellationError {
            return
        } catch {
            hasMore = false
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

    private func unique(_ values: [AnimeComment]) -> [AnimeComment] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private let videoID: String
    private let rootComment: AnimeComment
    private let client: AnimeAPIClient
    private let pageSize = 30
    private var currentPage = 0
    private var hasMore = true
}
