import Foundation

@MainActor
extension AnimeAPIClient {
    func fetchDetail(
        videoID: String,
        fallbackAnime: Anime? = nil
    ) async throws -> AnimeDetail {
        let contentKind = fallbackAnime?.contentKind ?? .anime
        let key = [
            detailCacheScope,
            contentKind.rawValue,
            videoID
        ].joined(separator: "|")
        let waiterID = UUID()
        let task: Task<AnimeDetail, Error>
        if var entry = detailTasks[key] {
            entry.waiters.insert(waiterID)
            detailTasks[key] = entry
            task = entry.task
        } else {
            task = Task<AnimeDetail, Error> { [weak self] in
                guard let self else {
                    throw AnimeAPIError.invalidResponse
                }
                return try await self.fetchDetailUncached(
                    videoID: videoID,
                    contentKind: contentKind,
                    fallbackAnime: fallbackAnime
                )
            }
            detailTasks[key] = DetailTaskEntry(
                task: task,
                waiters: [waiterID]
            )
        }

        defer {
            finishDetailWaiter(waiterID, forKey: key)
        }
        return try await withTaskCancellationHandler {
            do {
                let detail = try await task.value
                try Task.checkCancellation()
                return detail
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelDetailWaiter(waiterID, forKey: key)
            }
        }
    }

    private func fetchDetailUncached(
        videoID: String,
        contentKind: AnimeContentKind,
        fallbackAnime: Anime?
    ) async throws -> AnimeDetail {
        let payload = try await perform(
            settings.activePlatform.detailRequest(
                itemID: videoID,
                contentKind: contentKind
            )
        )
        let value = payload.value
        let domain = imageDomain(for: payload)
        let baseURL = settings.rootURL
        return try await mapPayload {
            try AnimeMapper.detail(
                from: value,
                domain: domain,
                baseURL: baseURL,
                fallbackAnime: fallbackAnime
            )
        }
    }

    private func cancelDetailWaiter(
        _ waiterID: UUID,
        forKey key: String
    ) {
        guard var entry = detailTasks[key] else { return }
        entry.waiters.remove(waiterID)
        if entry.waiters.isEmpty {
            entry.task.cancel()
            detailTasks[key] = nil
        } else {
            detailTasks[key] = entry
        }
    }

    private func finishDetailWaiter(
        _ waiterID: UUID,
        forKey key: String
    ) {
        guard var entry = detailTasks[key] else { return }
        entry.waiters.remove(waiterID)
        detailTasks[key] = entry.waiters.isEmpty ? nil : entry
    }

    func fetchRecommendations(
        videoID: String,
        contentKind: AnimeContentKind = .anime
    ) async throws -> [Anime] {
        let payload = try await perform(
            settings.activePlatform.recommendationsRequest(
                itemID: videoID,
                contentKind: contentKind
            )
        )
        let value = payload.value
        let domain = imageDomain(for: payload)
        let baseURL = settings.rootURL
        return try await mapPayload {
            AnimeMapper.animeList(
                from: value,
                domain: domain,
                baseURL: baseURL
            )
        }
    }

    func fetchComments(
        videoID: String,
        page: Int = 1,
        pageSize: Int = 100,
        parentID: String? = nil
    ) async throws -> [AnimeComment] {
        guard let request = settings.activePlatform.commentsRequest(
            videoID: videoID,
            page: page,
            pageSize: pageSize,
            parentID: parentID
        ) else {
            throw AnimeAPIError.commentsUnavailable
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

    func postComment(
        videoID: String,
        content rawContent: String,
        parentID: String? = nil,
        topID: String? = nil
    ) async throws {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty,
              let request = settings.activePlatform.postCommentRequest(
                  videoID: videoID,
                  content: content,
                  parentID: parentID,
                  topID: topID
              ) else {
            throw AnimeAPIError.commentPostingUnavailable
        }
        _ = try await perform(request)
    }
}
