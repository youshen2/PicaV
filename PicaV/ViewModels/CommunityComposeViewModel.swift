import Combine
import Foundation

@MainActor
final class CommunityComposeViewModel: ObservableObject {
    @Published private(set) var topics: [CommunityTopic] = []
    @Published private(set) var isLoadingTopics = false
    @Published private(set) var isPublishing = false
    @Published var errorMessage: String?

    init(client: AnimeAPIClient) {
        self.client = client
    }

    func loadTopics() async {
        guard topics.isEmpty, !isLoadingTopics else { return }
        isLoadingTopics = true
        defer { isLoadingTopics = false }
        do {
            topics = try await client.fetchCommunityTopics()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publish(content: String, selectedTopics: [CommunityTopic]) async -> Bool {
        guard !isPublishing else { return false }
        guard client.isAccountLoggedIn else {
            errorMessage = "请先登录平台账号，再发布动态。"
            return false
        }

        isPublishing = true
        defer { isPublishing = false }
        do {
            try await client.publishCommunityPost(
                content: content,
                topics: selectedTopics
            )
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private let client: AnimeAPIClient
}
