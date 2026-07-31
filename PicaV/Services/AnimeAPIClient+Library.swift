import Foundation

@MainActor
extension AnimeAPIClient {
    func fetchPlatformFavorites(
        page: Int = 1,
        pageSize: Int = 50
    ) async throws -> AnimePage {
        try requirePlatformLibraryAccountIfNeeded()
        guard let request = settings.activePlatform.favoritesRequest(
            page: page,
            pageSize: pageSize
        ) else {
            throw AnimeAPIError.platformLibraryUnavailable
        }
        let payload = try await perform(request)
        return try await animePage(
            from: payload,
            page: page,
            pageSize: pageSize
        )
    }

    func fetchPlatformHistory(
        page: Int = 1,
        pageSize: Int = 50
    ) async throws -> AnimePage {
        try requirePlatformLibraryAccountIfNeeded()
        guard let request = settings.activePlatform.historyRequest(
            page: page,
            pageSize: pageSize
        ) else {
            throw AnimeAPIError.platformLibraryUnavailable
        }
        let payload = try await perform(request)
        return try await animePage(
            from: payload,
            page: page,
            pageSize: pageSize
        )
    }

    func setPlatformFavorite(
        itemID: String,
        isFavorite: Bool
    ) async throws {
        try requirePlatformLibraryAccountIfNeeded()
        guard let request = settings.activePlatform.setFavoriteRequest(
            itemID: itemID,
            isFavorite: isFavorite
        ) else {
            throw AnimeAPIError.platformLibraryUnavailable
        }
        _ = try await perform(request)
    }

    func fetchCreatorProfile(userID: String) async throws -> AnimeUploader {
        guard let request = settings.activePlatform.creatorProfileRequest(
            userID: userID
        ) else {
            throw AnimeAPIError.creatorUnavailable
        }
        let payload = try await perform(request)
        let value = payload.value
        let domain = imageDomain(for: payload)
        let baseURL = settings.rootURL
        guard let uploader = try await mapPayload({
            AnimeMapper.uploader(
                from: value,
                domain: domain,
                baseURL: baseURL,
                fallbackID: userID
            )
        }) else {
            throw AnimeAPIError.invalidPayload
        }
        return uploader
    }

    func setCreatorFollowing(
        userID: String,
        isFollowing: Bool
    ) async throws {
        if creatorFollowingRequiresAccount, !settings.isAccountLoggedIn {
            throw AnimeAPIError.platformAccountRequired
        }
        guard let request = settings.activePlatform.setCreatorFollowingRequest(
            userID: userID,
            isFollowing: isFollowing
        ) else {
            throw AnimeAPIError.creatorUnavailable
        }
        _ = try await perform(request)
    }
}

