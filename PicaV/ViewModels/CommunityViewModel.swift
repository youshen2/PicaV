import Combine
import Foundation

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreErrorMessage: String?
    @Published private(set) var scope: CommunityFeedScope = .publicFeed
    @Published private(set) var sort: CommunityFeedSort = .latest
    @Published var interactionError: String?

    init(client: AnimeAPIClient) {
        self.client = client
    }

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }
        let requestID = UUID()
        activeRequestID = requestID
        invalidateLoadMore()
        let requestedScope = scope
        let requestedSort = sort
        if scope == .following,
           client.communityFollowingFeedRequiresAccount,
           !client.isAccountLoggedIn {
            posts = []
            hasMore = false
            state = .loaded
            return
        }

        state = .loading
        do {
            let result = try await client.fetchCommunityFeed(
                scope: requestedScope,
                sort: requestedSort,
                page: 1
            )
            guard !Task.isCancelled,
                  activeRequestID == requestID,
                  scope == requestedScope,
                  sort == requestedSort else {
                restoreStateAfterCancellation(requestID)
                return
            }
            posts = result.items.stableUniqued(id: \.id)
            page = result.page
            hasMore = result.hasMore
            loadMoreErrorMessage = nil
            state = .loaded
        } catch is CancellationError {
            restoreStateAfterCancellation(requestID)
        } catch {
            guard activeRequestID == requestID else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func selectScope(_ value: CommunityFeedScope) {
        guard scope != value else { return }
        scope = value
        scheduleReload()
    }

    func selectSort(_ value: CommunityFeedSort) {
        guard sort != value else { return }
        sort = value
        scheduleReload()
    }

    func loadMoreIfNeeded(current post: CommunityPost) async {
        guard state == .loaded,
              post.id == posts.last?.id,
              hasMore,
              !isLoadingMore else {
            return
        }
        let requestID = UUID()
        activeLoadMoreRequestID = requestID
        let requestedScope = scope
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
            let result = try await client.fetchCommunityFeed(
                scope: requestedScope,
                sort: requestedSort,
                page: nextPage
            )
            guard !Task.isCancelled,
                  activeLoadMoreRequestID == requestID,
                  scope == requestedScope,
                  sort == requestedSort else {
                return
            }
            posts.append(
                contentsOf: result.items.stableUniqued(
                    seededBy: Set(posts.map(\.id)),
                    id: \.id
                )
            )
            page = result.page
            hasMore = result.hasMore
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadMoreRequestID == requestID else { return }
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    func retryLoadMore() async {
        guard let post = posts.last else { return }
        await loadMoreIfNeeded(current: post)
    }

    func toggleLike(postID: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else {
            return
        }
        guard updatingLikePostIDs.insert(postID).inserted else { return }
        defer { updatingLikePostIDs.remove(postID) }
        guard !client.communityInteractionRequiresAccount
            || client.isAccountLoggedIn else {
            interactionError = "请先登录平台账号，再参与社区互动。"
            return
        }

        let original = posts[index]
        let target = !original.isLiked
        posts[index] = original.updatingLike(target)
        do {
            try await client.setCommunityPostLiked(postID: postID, liked: target)
        } catch {
            if let currentIndex = posts.firstIndex(where: { $0.id == postID }) {
                posts[currentIndex] = original
            }
            interactionError = error.localizedDescription
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await self?.load(force: true)
        }
    }

    private func invalidateLoadMore() {
        activeLoadMoreRequestID = nil
        isLoadingMore = false
        loadMoreErrorMessage = nil
    }

    private func restoreStateAfterCancellation(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        state = posts.isEmpty ? .idle : .loaded
    }

    private let client: AnimeAPIClient
    private var page = 1
    private var activeRequestID: UUID?
    private var activeLoadMoreRequestID: UUID?
    private var reloadTask: Task<Void, Never>?
    private var updatingLikePostIDs = Set<String>()
}
