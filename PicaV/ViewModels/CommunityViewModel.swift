import Combine
import Foundation

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published var scope: CommunityFeedScope = .publicFeed
    @Published var sort: CommunityFeedSort = .latest
    @Published var interactionError: String?

    init(client: AnimeAPIClient) {
        self.client = client
    }

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }
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
                scope: scope,
                sort: sort,
                page: 1
            )
            posts = result.items
            page = result.page
            hasMore = result.hasMore
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func selectScope(_ value: CommunityFeedScope) async {
        guard scope != value else { return }
        scope = value
        await load(force: true)
    }

    func selectSort(_ value: CommunityFeedSort) async {
        guard sort != value else { return }
        sort = value
        await load(force: true)
    }

    func loadMoreIfNeeded(current post: CommunityPost) async {
        guard post.id == posts.last?.id, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await client.fetchCommunityFeed(
                scope: scope,
                sort: sort,
                page: page + 1
            )
            let existing = Set(posts.map(\.id))
            posts.append(
                contentsOf: result.items.filter { !existing.contains($0.id) }
            )
            page = result.page
            hasMore = result.hasMore
        } catch {
            hasMore = false
        }
    }

    func toggleLike(postID: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else {
            return
        }
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

    private let client: AnimeAPIClient
    private var page = 1
}
