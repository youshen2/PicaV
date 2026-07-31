import Combine
import Foundation

@MainActor
final class AnimeDetailViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var detail: AnimeDetail?
    @Published private(set) var recommendations: [Anime] = []
    @Published private(set) var platformIsFavorite: Bool?
    @Published private(set) var isUpdatingFavorite = false
    @Published var favoriteErrorMessage: String?
    @Published private(set) var isUpdatingCreatorFollow = false
    @Published var creatorFollowErrorMessage: String?

    init(videoID: String, preview: Anime?, client: AnimeAPIClient) {
        self.videoID = videoID
        self.preview = preview
        self.client = client
    }

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }
        let requestID = UUID()
        activeLoadRequestID = requestID
        let requestedPlatformID = client.platformID
        let requestedCacheScope = client.detailCacheScope

        var hasCachedDetail = false
        if !force,
           let cached = await AnimeDetailCacheService.detail(
               videoID: videoID,
               platformID: requestedPlatformID,
               scope: requestedCacheScope
           ) {
            guard isCurrent(
                requestID,
                platformID: requestedPlatformID,
                cacheScope: requestedCacheScope
            ) else {
                return
            }
            detail = cached
            platformIsFavorite = cached.isFavorite
            state = .loaded
            hasCachedDetail = true
        } else if detail == nil {
            state = .loading
        }

        do {
            async let detailTask = client.fetchDetail(
                videoID: videoID,
                fallbackAnime: preview
            )
            async let recommendationsTask = client.fetchRecommendations(
                videoID: videoID,
                contentKind: preview?.contentKind ?? .anime
            )
            let loadedDetail = try await detailTask
            guard isCurrent(
                requestID,
                platformID: requestedPlatformID,
                cacheScope: requestedCacheScope
            ) else {
                restoreStateAfterCancellation(requestID)
                return
            }
            detail = loadedDetail
            platformIsFavorite = loadedDetail.isFavorite
            let loadedRecommendations =
                (try? await recommendationsTask) ?? []
            guard isCurrent(
                requestID,
                platformID: requestedPlatformID,
                cacheScope: requestedCacheScope
            ) else {
                restoreStateAfterCancellation(requestID)
                return
            }
            recommendations = loadedRecommendations
            state = .loaded
            await AnimeDetailCacheService.store(
                loadedDetail,
                videoID: videoID,
                platformID: requestedPlatformID,
                scope: requestedCacheScope
            )
            guard isCurrent(
                requestID,
                platformID: requestedPlatformID,
                cacheScope: requestedCacheScope
            ) else {
                return
            }
            await enrichUploaderIfNeeded(
                in: loadedDetail,
                requestID: requestID,
                platformID: requestedPlatformID,
                cacheScope: requestedCacheScope
            )
        } catch is CancellationError {
            restoreStateAfterCancellation(requestID)
        } catch {
            guard isCurrent(
                requestID,
                platformID: requestedPlatformID,
                cacheScope: requestedCacheScope
            ) else {
                restoreStateAfterCancellation(requestID)
                return
            }
            if !hasCachedDetail && detail == nil {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func setPlatformFavorite(_ isFavorite: Bool) async -> Bool {
        guard !isUpdatingFavorite else { return false }
        isUpdatingFavorite = true
        favoriteErrorMessage = nil
        defer { isUpdatingFavorite = false }

        do {
            try await client.setPlatformFavorite(
                itemID: videoID,
                isFavorite: isFavorite
            )
            platformIsFavorite = isFavorite
            return true
        } catch {
            favoriteErrorMessage = error.localizedDescription
            return false
        }
    }

    func setCreatorFollowing(_ isFollowing: Bool) async {
        guard let uploader = detail?.uploader,
              !isUpdatingCreatorFollow else {
            return
        }
        isUpdatingCreatorFollow = true
        creatorFollowErrorMessage = nil
        defer { isUpdatingCreatorFollow = false }

        do {
            try await client.setCreatorFollowing(
                userID: uploader.id,
                isFollowing: isFollowing
            )
            let updated = AnimeUploader(
                id: uploader.id,
                name: uploader.name,
                avatarURL: uploader.avatarURL,
                biography: uploader.biography,
                isFollowed: isFollowing
            )
            if let updatedDetail = detail?.replacingUploader(updated) {
                detail = updatedDetail
                await AnimeDetailCacheService.store(
                    updatedDetail,
                    videoID: videoID,
                    platformID: client.platformID,
                    scope: client.detailCacheScope
                )
            }
        } catch {
            creatorFollowErrorMessage = error.localizedDescription
        }
    }

    private func enrichUploaderIfNeeded(
        in loadedDetail: AnimeDetail,
        requestID: UUID,
        platformID: AnimePlatformID,
        cacheScope: String
    ) async {
        guard isCurrent(
            requestID,
            platformID: platformID,
            cacheScope: cacheScope
        ),
              client.supportsCreatorProfiles,
              let uploader = loadedDetail.uploader,
              let profile = try? await client.fetchCreatorProfile(
                  userID: uploader.id
              ) else {
            return
        }
        guard isCurrent(
            requestID,
            platformID: platformID,
            cacheScope: cacheScope
        ),
              detail?.id == loadedDetail.id else {
            return
        }
        let merged = AnimeUploader(
            id: profile.id,
            name: profile.name == "上传者"
                ? uploader.name
                : profile.name,
            avatarURL: profile.avatarURL ?? uploader.avatarURL,
            biography: profile.biography ?? uploader.biography,
            isFollowed: profile.isFollowed ?? uploader.isFollowed
        )
        let enrichedDetail = loadedDetail.replacingUploader(merged)
        detail = enrichedDetail
        await AnimeDetailCacheService.store(
            enrichedDetail,
            videoID: videoID,
            platformID: platformID,
            scope: cacheScope
        )
    }

    private func isCurrent(
        _ requestID: UUID,
        platformID: AnimePlatformID,
        cacheScope: String
    ) -> Bool {
        !Task.isCancelled
            && activeLoadRequestID == requestID
            && client.platformID == platformID
            && client.detailCacheScope == cacheScope
    }

    private func restoreStateAfterCancellation(_ requestID: UUID) {
        guard activeLoadRequestID == requestID else { return }
        state = detail == nil ? .idle : .loaded
    }

    private let videoID: String
    private let preview: Anime?
    private let client: AnimeAPIClient
    private var activeLoadRequestID: UUID?
}
