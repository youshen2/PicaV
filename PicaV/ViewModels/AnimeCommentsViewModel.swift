import Combine
import Foundation

@MainActor
final class AnimeCommentsViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var comments: [AnimeComment] = []
    @Published private(set) var isPosting = false
    @Published var postingError: String?

    init(videoID: String, client: AnimeAPIClient) {
        self.videoID = videoID
        self.client = client
    }

    let videoID: String

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }
        if comments.isEmpty {
            state = .loading
        }
        do {
            comments = try await client.fetchComments(videoID: videoID)
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func post(
        content rawContent: String,
        replyingTo comment: AnimeComment? = nil,
        topID: String? = nil
    ) async -> Bool {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isPosting else { return false }
        if client.commentPostingRequiresAccount, !client.isAccountLoggedIn {
            postingError = "请先在设置中登录平台账号，再发表评论。"
            return false
        }

        isPosting = true
        postingError = nil
        defer { isPosting = false }
        do {
            try await client.postComment(
                videoID: videoID,
                content: content,
                parentID: comment?.id,
                topID: topID ?? comment?.id
            )
            await load(force: true)
            return true
        } catch is CancellationError {
            return false
        } catch {
            postingError = error.localizedDescription
            return false
        }
    }

    private let client: AnimeAPIClient
}
