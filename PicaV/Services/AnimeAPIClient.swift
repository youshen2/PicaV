import Combine
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
    var autoplayNextEpisode: Bool {
        settings.autoplayNextEpisode
    }
    var downloadOverCellular: Bool {
        settings.downloadOverCellular
    }
    var isAppProxyEnabled: Bool {
        settings.appProxyEnabled
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
        injectedSession = session
    }

    func fetchCDNLines() async throws -> [CDNLine] {
        let payload = try await perform(settings.activePlatform.cdnLinesRequest())
        let value = payload.value
        return try await mapPayload {
            AnimeMapper.cdnLines(from: value)
        }
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

    func requirePlatformLibraryAccountIfNeeded() throws {
        guard !platformLibraryRequiresAccount || settings.isAccountLoggedIn else {
            throw AnimeAPIError.platformAccountRequired
        }
    }

    func perform(_ specification: PlatformRequest) async throws -> ServerPayload {
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

        let decryptionToken = settings.effectiveAccessToken
        let session = try injectedSession
            ?? AppNetworkSessionFactory.shared.session(
                for: settings.appNetworkRoute(),
                purpose: .api
            )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnimeAPIError.invalidResponse
        }
        return try await AnimeResponseParser.parse(
            data: data,
            statusCode: httpResponse.statusCode,
            travelerKey: travelerKey,
            timestamp: timestamp,
            accessToken: decryptionToken
        )
    }

    private func ensureAuthenticated() async throws {
        let platform = settings.activePlatform
        guard platform.requiresGuestSession,
              settings.effectiveAccessToken.isEmpty else {
            return
        }
        let scope = guestSessionScope

        if let entry = guestLoginTask, entry.scope == scope {
            let token = try await entry.task.value
            try Task.checkCancellation()
            guard guestSessionScope == scope else {
                throw CancellationError()
            }
            settings.setGuestToken(token)
            return
        }
        guestLoginTask?.task.cancel()

        let taskID = UUID()
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw AnimeAPIError.authenticationFailed }
            return try await self.createGuestSession(scope: scope)
        }
        guestLoginTask = GuestLoginTaskEntry(
            id: taskID,
            scope: scope,
            task: task
        )
        do {
            let token = try await task.value
            try Task.checkCancellation()
            guard guestSessionScope == scope else {
                throw CancellationError()
            }
            settings.setGuestToken(token)
            clearGuestLoginTask(id: taskID)
        } catch {
            clearGuestLoginTask(id: taskID)
            throw error
        }
    }

    private func createGuestSession(scope: String) async throws -> String {
        guard guestSessionScope == scope else {
            throw CancellationError()
        }
        guard let authentication = settings.activePlatform.guestAuthentication else {
            throw AnimeAPIError.authenticationFailed
        }
        let publicKeyPayload = try await send(
            PlatformRequest(
                path: authentication.publicKeyPath,
                requiresAuthentication: false
            )
        )
        try Task.checkCancellation()
        guard guestSessionScope == scope else {
            throw CancellationError()
        }
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
        try Task.checkCancellation()
        guard guestSessionScope == scope else {
            throw CancellationError()
        }
        rememberImageDomain(from: response)
        guard let token = accessToken(in: response.value), !token.isEmpty else {
            throw AnimeAPIError.authenticationFailed
        }
        return token
    }

    private func clearGuestLoginTask(id: UUID) {
        guard guestLoginTask?.id == id else { return }
        guestLoginTask = nil
    }

    func imageDomain(for payload: ServerPayload) -> String? {
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

    func endpointURL(path: String, query: [String: String]) -> URL? {
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

    func mapPayload<T>(
        _ transform: @escaping () throws -> T
    ) async throws -> T {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try transform()
        }
        return try await withTaskCancellationHandler {
            do {
                let value = try await task.value
                try Task.checkCancellation()
                return value
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            task.cancel()
        }
    }

    func animePage(
        from payload: ServerPayload,
        page: Int,
        pageSize: Int,
        contentKindHint: AnimeContentKind? = nil
    ) async throws -> AnimePage {
        let value = payload.value
        let domain = imageDomain(for: payload)
        let baseURL = settings.rootURL
        return try await mapPayload {
            let items = AnimeMapper.animeList(
                from: value,
                domain: domain,
                baseURL: baseURL,
                contentKindHint: contentKindHint
            )
            let total = AnimeMapper.totalCount(from: value)
            return AnimePage(
                items: items,
                page: page,
                hasMore: total.map { page * pageSize < $0 }
                    ?? (items.count >= pageSize)
            )
        }
    }

    let settings: AppSettings
    private let injectedSession: URLSession?
    private var guestSessionScope: String {
        [
            settings.platformID.rawValue,
            settings.rootURL.absoluteString,
            settings.normalizedAPIPrefix
        ].joined(separator: "|")
    }

    private struct GuestLoginTaskEntry {
        let id: UUID
        let scope: String
        let task: Task<String, Error>
    }

    private var guestLoginTask: GuestLoginTaskEntry?
    struct DetailTaskEntry {
        let task: Task<AnimeDetail, Error>
        var waiters: Set<UUID>
    }

    var detailTasks: [String: DetailTaskEntry] = [:]
}
