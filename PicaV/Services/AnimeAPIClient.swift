import Combine
import CommonCrypto
import CryptoKit
import Foundation

enum AnimeAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, message: String?)
    case server(code: Int, message: String)
    case invalidPayload
    case missingDecryptionKey
    case decryptionFailed
    case authenticationFailed
    case accountAuthenticationUnavailable
    case accountValidation(String)
    case playbackUnavailable
    case commentsUnavailable
    case commentPostingUnavailable
    case communityUnavailable
    case communityInteractionUnavailable
    case communityPublishingUnavailable
    case invalidCommunityPayload
    case platformLibraryUnavailable
    case platformAccountRequired
    case homeSectionActionUnavailable
    case creatorUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址无效，请在设置中检查。"
        case .invalidResponse:
            return "服务器返回了无法识别的响应。"
        case .httpStatus(let status, let message):
            return message ?? "网络请求失败（HTTP \(status)）。"
        case .server(_, let message):
            return message
        case .invalidPayload:
            return "番剧数据格式有误。"
        case .missingDecryptionKey:
            return "此响应需要有效会话才能解密。"
        case .decryptionFailed:
            return "响应解密失败，请重新建立会话后再试。"
        case .authenticationFailed:
            return "平台游客会话建立失败。"
        case .accountAuthenticationUnavailable:
            return "当前平台暂不支持账号登录。"
        case .accountValidation(let message):
            return message
        case .playbackUnavailable:
            return "当前剧集暂时没有可用播放源。"
        case .commentsUnavailable:
            return "当前平台暂不支持评论区。"
        case .commentPostingUnavailable:
            return "当前平台暂不支持发表评论。"
        case .communityUnavailable:
            return "当前平台暂不支持社区。"
        case .communityInteractionUnavailable:
            return "当前平台暂不支持这项社区互动。"
        case .communityPublishingUnavailable:
            return "当前平台暂不支持发布动态。"
        case .invalidCommunityPayload:
            return "社区数据格式有误。"
        case .platformLibraryUnavailable:
            return "当前平台暂不支持收藏或浏览记录。"
        case .platformAccountRequired:
            return "请先登录当前平台账号。"
        case .homeSectionActionUnavailable:
            return "当前平台暂不支持这个首页栏目操作。"
        case .creatorUnavailable:
            return "当前平台暂不支持上传者资料或关注。"
        }
    }
}

private struct ServerPayload {
    let value: Any
    let domain: String?
}

@MainActor
final class AnimeAPIClient: ObservableObject {
    var platformID: AnimePlatformID { settings.platformID }
    var platformName: String { settings.activePlatform.displayName }
    var supportsComments: Bool {
        settings.activePlatform.commentCapability != nil
    }
    var supportsCommentPosting: Bool {
        settings.activePlatform.commentCapability?.supportsPosting == true
    }
    var commentPostingRequiresAccount: Bool {
        settings.activePlatform.commentCapability?.requiresAccountToPost == true
    }
    var supportsCommunity: Bool {
        settings.activePlatform.communityCapability != nil
    }
    var supportsCommunityPublishing: Bool {
        settings.activePlatform.communityCapability?.supportsPosting == true
    }
    var supportsCommunityFollowingFeed: Bool {
        settings.activePlatform.communityCapability?.supportsFollowingFeed == true
    }
    var communityInteractionRequiresAccount: Bool {
        settings.activePlatform.communityCapability?.requiresAccountForInteraction == true
    }
    var communityFollowingFeedRequiresAccount: Bool {
        settings.activePlatform.communityCapability?.requiresAccountForFollowingFeed == true
    }
    var supportsPlatformFavorites: Bool {
        settings.activePlatform.libraryCapability?.supportsFavorites == true
    }
    var supportsPlatformHistory: Bool {
        settings.activePlatform.libraryCapability?.supportsHistory == true
    }
    var platformLibraryRequiresAccount: Bool {
        settings.activePlatform.libraryCapability?.requiresAccount == true
    }
    var supportsCreatorProfiles: Bool {
        settings.activePlatform.creatorCapability?.supportsProfiles == true
    }
    var supportsCreatorFollowing: Bool {
        settings.activePlatform.creatorCapability?.supportsFollowing == true
    }
    var creatorFollowingRequiresAccount: Bool {
        settings.activePlatform.creatorCapability?
            .requiresAccountForFollowing == true
    }
    var homeChannels: [PlatformHomeChannel] {
        settings.activePlatform.homeChannels
    }
    var isAccountLoggedIn: Bool { settings.isAccountLoggedIn }
    var currentAccountUserID: String? {
        settings.accountSession?.userID
    }
    var preferredCDNID: String? {
        settings.preferredCDNID.isEmpty ? nil : settings.preferredCDNID
    }
    var detailCacheScope: String {
        let account = settings.accountSession.map {
            $0.userID ?? $0.account
        } ?? "guest"
        return [
            settings.rootURL.absoluteString,
            settings.normalizedAPIPrefix,
            account
        ].joined(separator: "|")
    }

    init(settings: AppSettings, session: URLSession? = nil) {
        self.settings = settings
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 45
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.httpMaximumConnectionsPerHost = 6
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchHomeSections(
        channel: PlatformHomeChannel
    ) async throws -> [AnimeHomeSection] {
        if let request = settings.activePlatform.homeSectionsRequest(
            channel: channel
        ) {
            let payload = try await perform(request)
            return AnimeMapper.homeSections(
                from: payload.value,
                domain: imageDomain(for: payload),
                baseURL: settings.rootURL,
                contentKindHint: channel.contentKindHint
            )
        }

        guard let categoriesRequest = settings.activePlatform
            .homeCatalogCategoriesRequest(channel: channel) else {
            return []
        }
        let categoriesPayload = try await perform(categoriesRequest)
        let categories = AnimeMapper.categories(
            from: categoriesPayload.value,
            domain: imageDomain(for: categoriesPayload),
            baseURL: settings.rootURL
        )
        guard let categoryID = categories.first?.id,
              let catalogRequest = settings.activePlatform.homeCatalogRequest(
                  channel: channel,
                  categoryID: categoryID,
                  pageSize: 20
              ) else {
            return []
        }
        let catalogPayload = try await perform(catalogRequest)
        let items = AnimeMapper.animeList(
            from: catalogPayload.value,
            domain: imageDomain(for: catalogPayload),
            baseURL: settings.rootURL,
            contentKindHint: channel.contentKindHint
        )
        guard !items.isEmpty else { return [] }
        return [
            AnimeHomeSection(
                id: "catalog-\(channel.id)-\(categoryID)",
                title: channel.contentKindHint == .video
                    ? "最新视频"
                    : "新番速递",
                subtitle: categories.first?.title,
                layout: channel.contentKindHint == .video
                    ? .landscape
                    : .portrait,
                items: items
            )
        ]
    }

    func fetchHomeSectionMore(
        section: AnimeHomeSection,
        page: Int,
        pageSize: Int = 20,
        sortType: Int
    ) async throws -> AnimePage {
        guard let actions = section.actions,
              let request = settings.activePlatform.homeSectionMoreRequest(
                  sectionID: actions.sectionID,
                  page: page,
                  pageSize: pageSize,
                  sortType: sortType
              ) else {
            throw AnimeAPIError.homeSectionActionUnavailable
        }
        let payload = try await perform(request)
        let items = AnimeMapper.animeList(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL,
            contentKindHint: section.items.first?.contentKind
        )
        let total = AnimeMapper.totalCount(from: payload.value)
        return AnimePage(
            items: items,
            page: page,
            hasMore: total.map { page * pageSize < $0 }
                ?? (items.count >= pageSize)
        )
    }

    func fetchHomeSectionReplacement(
        section: AnimeHomeSection
    ) async throws -> [Anime] {
        guard let actions = section.actions,
              let lastItemID = section.items.last?.id,
              let request = settings.activePlatform.homeSectionChangeRequest(
                  sectionID: actions.sectionID,
                  lastItemID: lastItemID,
                  pageSize: actions.changePageSize
              ) else {
            throw AnimeAPIError.homeSectionActionUnavailable
        }
        let payload = try await perform(request)
        return AnimeMapper.animeList(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL,
            contentKindHint: section.items.first?.contentKind
        )
    }

    func fetchCategories() async throws -> [AnimeCategory] {
        let payload = try await perform(settings.activePlatform.categoriesRequest())
        return AnimeMapper.categories(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        )
    }

    func fetchAnime(
        categoryID: String?,
        page: Int,
        pageSize: Int = 10,
        sort: AnimeSort
    ) async throws -> AnimePage {
        let specification = settings.activePlatform.catalogRequest(
            categoryID: categoryID,
            page: page,
            pageSize: pageSize,
            sort: sort
        )
        let payload = try await perform(specification)
        let items = AnimeMapper.animeList(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        )
        let total = AnimeMapper.totalCount(from: payload.value)
        return AnimePage(
            items: items,
            page: page,
            hasMore: total.map { page * pageSize < $0 } ?? (items.count >= pageSize)
        )
    }

    func search(
        query searchWord: String,
        page: Int,
        pageSize: Int = 20
    ) async throws -> AnimePage {
        let specification = settings.activePlatform.searchRequest(
            query: searchWord,
            page: page,
            pageSize: pageSize
        )
        let payload = try await perform(specification)
        let items = AnimeMapper.animeList(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        )
        let total = AnimeMapper.totalCount(from: payload.value)
        return AnimePage(
            items: items,
            page: page,
            hasMore: total.map { page * pageSize < $0 } ?? (items.count >= pageSize)
        )
    }

    func fetchSearchHotWords() async throws -> [String] {
        guard let request = settings.activePlatform.searchHotWordsRequest() else {
            return []
        }
        let payload = try await perform(request)
        return AnimeMapper.searchHotWords(from: payload.value)
    }

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
        let items = AnimeMapper.animeList(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        )
        let total = AnimeMapper.totalCount(from: payload.value)
        return AnimePage(
            items: items,
            page: page,
            hasMore: total.map { page * pageSize < $0 }
                ?? (items.count >= pageSize)
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
        let items = AnimeMapper.animeList(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        )
        let total = AnimeMapper.totalCount(from: payload.value)
        return AnimePage(
            items: items,
            page: page,
            hasMore: total.map { page * pageSize < $0 }
                ?? (items.count >= pageSize)
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
        guard let uploader = AnimeMapper.uploader(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL,
            fallbackID: userID
        ) else {
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

    func fetchDetail(videoID: String, fallbackAnime: Anime? = nil) async throws -> AnimeDetail {
        let contentKind = fallbackAnime?.contentKind ?? .anime
        let payload = try await perform(
            settings.activePlatform.detailRequest(
                itemID: videoID,
                contentKind: contentKind
            )
        )
        return try AnimeMapper.detail(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL,
            fallbackAnime: fallbackAnime
        )
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
        return AnimeMapper.animeList(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        )
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
        return AnimeMapper.comments(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        )
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
        let items = CommunityMapper.posts(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        )
        let total = AnimeMapper.totalCount(from: payload.value)
        return CommunityFeedPage(
            items: items,
            page: page,
            hasMore: total.map { page * pageSize < $0 } ?? (items.count >= pageSize)
        )
    }

    func fetchCommunityPost(postID: String) async throws -> CommunityPost {
        guard let request = settings.activePlatform.communityDetailRequest(
            postID: postID
        ) else {
            throw AnimeAPIError.communityUnavailable
        }
        let payload = try await perform(request)
        guard let post = CommunityMapper.post(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        ) else {
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
        return AnimeMapper.comments(
            from: payload.value,
            domain: imageDomain(for: payload),
            baseURL: settings.rootURL
        )
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
        return CommunityMapper.topics(from: payload.value)
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

    func fetchCDNLines() async throws -> [CDNLine] {
        let payload = try await perform(settings.activePlatform.cdnLinesRequest())
        return AnimeMapper.cdnLines(from: payload.value)
    }

    @discardableResult
    func authenticate(
        account rawAccount: String,
        password: String,
        action: PlatformAccountAction
    ) async throws -> PlatformAccountSession {
        let account = rawAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let authentication = settings.activePlatform.accountAuthentication else {
            throw AnimeAPIError.accountAuthenticationUnavailable
        }
        if let message = authentication.rules.accountError(account) {
            throw AnimeAPIError.accountValidation(message)
        }
        if let message = authentication.rules.passwordError(password) {
            throw AnimeAPIError.accountValidation(message)
        }

        let publicKeyPayload = try await send(
            PlatformRequest(
                path: authentication.publicKeyPath,
                requiresAuthentication: false
            )
        )
        guard let publicKey = string(
            for: ["publicKey", "public_key"],
            in: publicKeyPayload.value
        ) else {
            throw AnimeAPIError.authenticationFailed
        }

        let parameters: JSONObject = ["account": account, "password": password]
        let encryptedBody: JSONObject
        switch authentication.credentialEncryption {
        case .rsaOAEP256AESGCM:
            encryptedBody = try AcFanAuthenticationCrypto.encryptParameters(
                parameters,
                publicKeyPEM: publicKey
            )
        }

        let path: String
        let requiresAuthentication: Bool
        switch action {
        case .login:
            path = authentication.loginPath
            requiresAuthentication = settings.activePlatform.requiresGuestSession
                || !settings.effectiveAccessToken.isEmpty
        case .register:
            let hasAuthenticatedSession = settings.activePlatform.requiresGuestSession
                || !settings.effectiveAccessToken.isEmpty
            path = hasAuthenticatedSession
                ? authentication.authenticatedRegistrationPath
                : authentication.publicRegistrationPath
            requiresAuthentication = hasAuthenticatedSession
        }

        let response = try await perform(
            PlatformRequest(
                method: .post,
                path: path,
                body: encryptedBody,
                requiresAuthentication: requiresAuthentication,
                isSensitive: true
            )
        )
        guard let token = accessToken(in: response.value), !token.isEmpty else {
            throw AnimeAPIError.authenticationFailed
        }

        let session = accountSession(in: response.value, fallbackAccount: account)
        settings.setAccountSession(session, accessToken: token)
        return session
    }

    func playbackURL(for detail: AnimeDetail, cdnID: String? = nil) throws -> URL {
        let preferred = cdnID
            ?? (!settings.preferredCDNID.isEmpty ? settings.preferredCDNID : detail.cdnID)
        guard let specification = settings.activePlatform.playbackRequest(
            detail: detail,
            cdnID: preferred
        ), let url = endpointURL(path: specification.path, query: specification.query) else {
            throw AnimeAPIError.playbackUnavailable
        }
        return url
    }

    func downloadPlaybackURL(
        anime: Anime,
        episodeID: String
    ) async throws -> URL {
        let detail = try await fetchDetail(
            videoID: episodeID,
            fallbackAnime: anime
        )
        return try playbackURL(
            for: detail,
            cdnID: preferredCDNID ?? detail.cdnID
        )
    }

    func setPreferredCDNID(_ id: String) {
        settings.preferredCDNID = id
    }

    private func requirePlatformLibraryAccountIfNeeded() throws {
        guard !platformLibraryRequiresAccount || settings.isAccountLoggedIn else {
            throw AnimeAPIError.platformAccountRequired
        }
    }

    private func perform(_ specification: PlatformRequest) async throws -> ServerPayload {
        do {
            let payload = try await send(specification)
            rememberImageDomain(from: payload)
            return payload
        } catch AnimeAPIError.server(let code, _)
            where [1001, 1003].contains(code)
                && settings.accessToken.isEmpty
                && settings.guestSessionActive {
            settings.invalidateGuestSession()
            let payload = try await send(specification)
            rememberImageDomain(from: payload)
            return payload
        }
    }

    private func send(
        _ specification: PlatformRequest,
        travelerKey: String? = nil
    ) async throws -> ServerPayload {
        if specification.requiresAuthentication {
            try await ensureAuthenticated()
        }

        var query = specification.query
        if specification.method == .get {
            query["_t"] = String(Int64(Date().timeIntervalSince1970 * 1_000))
        }
        guard let url = endpointURL(path: specification.path, query: query) else {
            throw AnimeAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = specification.method.rawValue
        request.timeoutInterval = 30
        let timestamp = applyHeaders(
            to: &request,
            includeAuthentication: specification.requiresAuthentication
        )
        if let body = specification.body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        if specification.isSensitive {
            switch settings.activePlatform.sensitiveSigningScheme {
            case .none:
                break
            case .acFanSHA256:
                let headers = try AcFanAuthenticationCrypto.sensitiveHeaders(
                    method: specification.method,
                    path: url.path,
                    body: specification.body
                )
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnimeAPIError.invalidResponse
        }

        let parsedObject = try? JSONSerialization.jsonObject(with: data)
        let parsedRoot = parsedObject as? JSONObject
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AnimeAPIError.httpStatus(
                httpResponse.statusCode,
                message: parsedRoot?.string(for: ["msg", "message", "error"])
            )
        }
        guard let root = parsedRoot else {
            throw AnimeAPIError.invalidResponse
        }
        return try parsePayload(root, travelerKey: travelerKey, timestamp: timestamp)
    }

    private func parsePayload(
        _ root: JSONObject,
        travelerKey: String?,
        timestamp: String
    ) throws -> ServerPayload {
        if let code = root.integer(for: ["code", "status"]), code != 0, code != 200 {
            throw AnimeAPIError.server(
                code: code,
                message: root.string(for: ["msg", "message", "error"]) ?? "请求失败（\(code)）"
            )
        }

        let dataObject = root.object(for: ["data", "result"])
        let rootDomain = root.string(for: ["domain", "imgDomain", "imageDomain"])
            ?? dataObject?.string(for: ["domain", "imgDomain", "imageDomain"])

        if let travelerKey,
           let encrypted = root.string(for: ["data"]) {
            let value = try AcFanAuthenticationCrypto.decryptTravelerResponse(
                encrypted,
                travelerKey: travelerKey,
                timestamp: timestamp
            )
            return normalizedPayload(value, fallbackDomain: rootDomain)
        }

        let encrypted = root.string(for: ["encData"]) ?? dataObject?.string(for: ["encData"])
        if let encrypted {
            return normalizedPayload(
                try decryptJSON(encrypted),
                fallbackDomain: rootDomain
            )
        }
        return ServerPayload(
            value: root.value(for: ["data", "result"]) ?? root,
            domain: rootDomain
        )
    }

    private func ensureAuthenticated() async throws {
        let platform = settings.activePlatform
        guard platform.requiresGuestSession, settings.effectiveAccessToken.isEmpty else { return }

        if let guestLoginTask {
            let token = try await guestLoginTask.value
            settings.setGuestToken(token)
            return
        }

        let task = Task<String, Error> { [weak self] in
            guard let self else { throw AnimeAPIError.authenticationFailed }
            return try await self.createGuestSession()
        }
        guestLoginTask = task
        do {
            let token = try await task.value
            settings.setGuestToken(token)
            guestLoginTask = nil
        } catch {
            guestLoginTask = nil
            throw error
        }
    }

    private func createGuestSession() async throws -> String {
        guard let authentication = settings.activePlatform.guestAuthentication else {
            throw AnimeAPIError.authenticationFailed
        }
        let publicKeyPayload = try await send(
            PlatformRequest(
                path: authentication.publicKeyPath,
                requiresAuthentication: false
            )
        )
        guard let publicKey = string(
            for: ["publicKey", "public_key"],
            in: publicKeyPayload.value
        ) else {
            throw AnimeAPIError.authenticationFailed
        }

        let travelerKey: String
        let encryptedBody: JSONObject
        switch authentication.scheme {
        case .travelerV1:
            travelerKey = try AcFanAuthenticationCrypto.makeTravelerKey()
            encryptedBody = try AcFanAuthenticationCrypto.encryptParameters(
                [
                    "projectType": authentication.projectType,
                    "code": "{}",
                    "deviceId": settings.deviceID
                ],
                publicKeyPEM: publicKey
            )
        }
        let response = try await send(
            PlatformRequest(
                method: .post,
                path: authentication.loginPath(key: travelerKey),
                body: encryptedBody,
                requiresAuthentication: false,
                isSensitive: true
            ),
            travelerKey: travelerKey
        )
        rememberImageDomain(from: response)
        guard let token = accessToken(in: response.value), !token.isEmpty else {
            throw AnimeAPIError.authenticationFailed
        }
        return token
    }

    private func imageDomain(for payload: ServerPayload) -> String? {
        payload.domain ?? settings.effectiveImageDomain
    }

    private func rememberImageDomain(from payload: ServerPayload) {
        settings.setImageDomain(payload.domain ?? imageDomain(in: payload.value))
    }

    private func imageDomain(in value: Any, depth: Int = 0) -> String? {
        guard depth < 6 else { return nil }
        if let object = value as? JSONObject {
            if let domain = object.string(for: ["imgDomain", "imageDomain"]) {
                return domain
            }
            for key in ["data", "result", "userInfo", "user", "accountInfo"] {
                if let nested = object[key],
                   let domain = imageDomain(in: nested, depth: depth + 1) {
                    return domain
                }
            }
        } else if let values = value as? [Any] {
            for value in values {
                if let domain = imageDomain(in: value, depth: depth + 1) {
                    return domain
                }
            }
        }
        return nil
    }

    private func accessToken(in value: Any) -> String? {
        if let object = value as? JSONObject {
            if let token = object.string(
                for: ["token", "accessToken", "access_token", "authorization", "aut"]
            ) {
                return token
            }
            for key in ["data", "result", "userInfo", "user", "accountInfo"] {
                if let nested = object[key], let token = accessToken(in: nested) {
                    return token
                }
            }
        }
        if let values = value as? [Any] {
            for value in values {
                if let token = accessToken(in: value) { return token }
            }
        }
        return nil
    }

    private func accountSession(
        in value: Any,
        fallbackAccount: String
    ) -> PlatformAccountSession {
        let object = accountObject(in: value)
        let displayName = object?.string(
            for: ["nickName", "nickname", "userName", "username", "account"]
        ) ?? fallbackAccount
        return PlatformAccountSession(
            platformID: settings.platformID,
            account: object?.string(for: ["account", "userAccount"]) ?? fallbackAccount,
            displayName: displayName,
            userID: object?.string(for: ["userId", "userID", "uid", "id"]),
            loggedInAt: Date()
        )
    }

    private func accountObject(in value: Any, depth: Int = 0) -> JSONObject? {
        guard depth < 6 else { return nil }
        if let object = value as? JSONObject {
            if object.value(
                for: ["userId", "userID", "uid", "account", "userAccount", "nickname", "nickName"]
            ) != nil {
                return object
            }
            for key in ["data", "result", "userInfo", "user", "accountInfo"] {
                if let nested = object[key],
                   let result = accountObject(in: nested, depth: depth + 1) {
                    return result
                }
            }
        }
        return nil
    }

    private func string(for keys: [String], in value: Any, depth: Int = 0) -> String? {
        guard depth < 6 else { return nil }
        if let object = value as? JSONObject {
            if let string = object.string(for: keys) { return string }
            for key in ["data", "result"] {
                if let nested = object[key],
                   let string = string(for: keys, in: nested, depth: depth + 1) {
                    return string
                }
            }
        }
        return nil
    }

    private func normalizedPayload(
        _ value: Any,
        fallbackDomain: String?
    ) -> ServerPayload {
        guard let object = value as? JSONObject else {
            return ServerPayload(value: value, domain: fallbackDomain)
        }
        let domain = object.string(for: ["domain", "imgDomain", "imageDomain"])
            ?? object.object(for: ["data", "result"])?.string(
                for: ["domain", "imgDomain", "imageDomain"]
            )
            ?? fallbackDomain
        let isEnvelope = object.value(for: ["code", "status"]) != nil
            || (object.value(for: ["domain", "imgDomain", "imageDomain"]) != nil
                && object.value(for: ["data", "result"]) != nil)
        if isEnvelope, let nested = object.value(for: ["data", "result"]) {
            return ServerPayload(value: nested, domain: domain)
        }
        return ServerPayload(value: object, domain: domain)
    }

    private func endpointURL(path: String, query: [String: String]) -> URL? {
        let endpoint = settings.apiBaseURL.appendingPathComponent(
            path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }

    @discardableResult
    private func applyHeaders(
        to request: inout URLRequest,
        includeAuthentication: Bool
    ) -> String {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1_000))
        let signatureInput = String(timestamp.dropFirst(3).prefix(5))
        let signature = Insecure.MD5.hash(data: Data(signatureInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let platform = settings.activePlatform

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        switch platform.requestHeaderScheme {
        case .standard:
            if includeAuthentication, !settings.effectiveAccessToken.isEmpty {
                request.setValue(
                    "Bearer \(settings.effectiveAccessToken)",
                    forHTTPHeaderField: "Authorization"
                )
            }
        case .acFanV1:
            request.setValue(timestamp, forHTTPHeaderField: "t")
            request.setValue(signature, forHTTPHeaderField: "s")
            request.setValue(platform.userMark, forHTTPHeaderField: "User-Mark")
            request.setValue(settings.deviceID, forHTTPHeaderField: "deviceId")
            request.setValue("iOS", forHTTPHeaderField: "device")
            request.setValue(platform.appVersion, forHTTPHeaderField: "appVersion")
            request.setValue(settings.requestSID, forHTTPHeaderField: "sid")
            if includeAuthentication, !settings.effectiveAccessToken.isEmpty {
                request.setValue(settings.effectiveAccessToken, forHTTPHeaderField: "aut")
            }
        }
        return timestamp
    }

    private func decryptJSON(_ encrypted: String) throws -> Any {
        let keyString = String(settings.effectiveAccessToken.dropFirst(2).prefix(16))
        guard keyString.utf8.count == kCCKeySizeAES128 else {
            throw AnimeAPIError.missingDecryptionKey
        }
        guard let encryptedData = Data(base64Encoded: encrypted) else {
            throw AnimeAPIError.decryptionFailed
        }

        let key = Data(keyString.utf8)
        var output = Data(count: encryptedData.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            encryptedData.withUnsafeBytes { encryptedBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        key.count,
                        keyBytes.baseAddress,
                        encryptedBytes.baseAddress,
                        encryptedData.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw AnimeAPIError.decryptionFailed }
        output.removeSubrange(outputLength..<output.count)
        return try JSONSerialization.jsonObject(with: output)
    }

    private let settings: AppSettings
    private let session: URLSession
    private var guestLoginTask: Task<String, Error>?
}
