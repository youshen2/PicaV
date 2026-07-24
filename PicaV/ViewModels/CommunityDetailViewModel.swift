import Combine
import Foundation

@MainActor
final class CommunityDetailViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var post: CommunityPost
    @Published private(set) var comments: [AnimeComment] = []
    @Published private(set) var isPosting = false
    @Published private(set) var isUpdatingLike = false
    @Published var interactionError: String?

    init(post: CommunityPost, client: AnimeAPIClient) {
        self.post = post
        self.client = client
    }

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }
        if post.content.isEmpty {
            state = .loading
        }
        do {
            async let postRequest = client.fetchCommunityPost(postID: post.id)
            async let commentsRequest = client.fetchCommunityComments(postID: post.id)
            let (loadedPost, loadedComments) = try await (
                postRequest,
                commentsRequest
            )
            post = loadedPost
            comments = loadedComments
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func toggleLike() async {
        guard !isUpdatingLike else { return }
        guard !client.communityInteractionRequiresAccount
            || client.isAccountLoggedIn else {
            interactionError = "请先登录平台账号，再参与社区互动。"
            return
        }

        isUpdatingLike = true
        let original = post
        let target = !post.isLiked
        post = post.updatingLike(target)
        defer { isUpdatingLike = false }
        do {
            try await client.setCommunityPostLiked(postID: post.id, liked: target)
        } catch {
            post = original
            interactionError = error.localizedDescription
        }
    }

    func postComment(
        content rawContent: String,
        parentID: String? = nil,
        topID: String? = nil
    ) async -> Bool {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isPosting else { return false }
        guard !client.communityInteractionRequiresAccount
            || client.isAccountLoggedIn else {
            interactionError = "请先登录平台账号，再发表评论。"
            return false
        }

        isPosting = true
        defer { isPosting = false }
        do {
            try await client.postCommunityComment(
                postID: post.id,
                content: content,
                parentID: parentID,
                topID: topID
            )
            comments = try await client.fetchCommunityComments(postID: post.id)
            return true
        } catch is CancellationError {
            return false
        } catch {
            interactionError = error.localizedDescription
            return false
        }
    }

    private let client: AnimeAPIClient
}

@MainActor
final class CommunityThreadViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var replies: [AnimeComment] = []

    init(postID: String, rootComment: AnimeComment, client: AnimeAPIClient) {
        self.postID = postID
        self.rootComment = rootComment
        self.client = client
        replies = rootComment.replies
    }

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }
        state = replies.isEmpty ? .loading : .loaded
        do {
            replies = try await client.fetchCommunityComments(
                postID: postID,
                parentID: rootComment.id
            )
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private let postID: String
    private let rootComment: AnimeComment
    private let client: AnimeAPIClient
}
