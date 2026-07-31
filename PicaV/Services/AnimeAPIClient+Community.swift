import Foundation

@MainActor
extension AnimeAPIClient {
    func fetchCommunityFeed(
        scope: CommunityFeedScope,
        sort: CommunityFeedSort,
        page: Int,
        pageSize: Int = 10
    ) async throws -> CommunityFeedPage {
        guard let request = settings.activePlatform.communityFeedRequest(
            scope: scope,
            sort: sort,
            page: page,
            pageSize: pageSize
        ) else {
            throw AnimeAPIError.communityUnavailable
        }
        let payload = try await perform(request)
        let value = payload.value
        let domain = imageDomain(for: payload)
        let baseURL = settings.rootURL
        return try await mapPayload {
            let items = CommunityMapper.posts(
                from: value,
                domain: domain,
                baseURL: baseURL
            )
            let total = AnimeMapper.totalCount(from: value)
            return CommunityFeedPage(
                items: items,
                page: page,
                hasMore: total.map { page * pageSize < $0 }
                    ?? (items.count >= pageSize)
            )
        }
    }

    func fetchCommunityPost(postID: String) async throws -> CommunityPost {
        guard let request = settings.activePlatform.communityDetailRequest(
            postID: postID
        ) else {
            throw AnimeAPIError.communityUnavailable
        }
        let payload = try await perform(request)
        let value = payload.value
        let domain = imageDomain(for: payload)
        let baseURL = settings.rootURL
        guard let post = try await mapPayload({
            CommunityMapper.post(
                from: value,
                domain: domain,
                baseURL: baseURL
            )
        }) else {
            throw AnimeAPIError.invalidCommunityPayload
        }
        return post
    }

    func setCommunityPostLiked(postID: String, liked: Bool) async throws {
        guard let request = settings.activePlatform.communityLikeRequest(
            postID: postID,
            liked: liked
        ) else {
            throw AnimeAPIError.communityInteractionUnavailable
        }
        _ = try await perform(request)
    }

    func fetchCommunityComments(
        postID: String,
        page: Int = 1,
        pageSize: Int = 100,
        parentID: String? = nil
    ) async throws -> [AnimeComment] {
        guard let request = settings.activePlatform.communityCommentsRequest(
            postID: postID,
            page: page,
            pageSize: pageSize,
            parentID: parentID
        ) else {
            throw AnimeAPIError.communityInteractionUnavailable
        }
        let payload = try await perform(request)
        let value = payload.value
        let domain = imageDomain(for: payload)
        let baseURL = settings.rootURL
        return try await mapPayload {
            AnimeMapper.comments(
                from: value,
                domain: domain,
                baseURL: baseURL
            )
        }
    }

    func postCommunityComment(
        postID: String,
        content rawContent: String,
        parentID: String? = nil,
        topID: String? = nil
    ) async throws {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty,
              let request = settings.activePlatform.postCommunityCommentRequest(
                  postID: postID,
                  content: content,
                  parentID: parentID,
                  topID: topID
              ) else {
            throw AnimeAPIError.communityInteractionUnavailable
        }
        _ = try await perform(request)
    }

    func fetchCommunityTopics() async throws -> [CommunityTopic] {
        guard let request = settings.activePlatform.communityTopicsRequest() else {
            throw AnimeAPIError.communityPublishingUnavailable
        }
        let payload = try await perform(request)
        let value = payload.value
        return try await mapPayload {
            CommunityMapper.topics(from: value)
        }
    }

    func publishCommunityPost(
        content rawContent: String,
        topics: [CommunityTopic]
    ) async throws {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !topics.isEmpty,
              let request = settings.activePlatform.publishCommunityPostRequest(
                  content: content,
                  topics: topics
              ) else {
            throw AnimeAPIError.communityPublishingUnavailable
        }
        _ = try await perform(request)
    }

    func communityPlaybackURL(for video: CommunityVideo) throws -> URL {
        guard !video.isLocked,
              let request = settings.activePlatform.communityVideoPlaybackRequest(
                  videoPath: video.path
              ),
              let url = endpointURL(path: request.path, query: request.query) else {
            throw AnimeAPIError.playbackUnavailable
        }
        return url
    }
}

