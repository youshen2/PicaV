import Foundation

enum AnimePlatformID: String, CaseIterable, Codable, Identifiable {
    case acFan = "acfan"

    var id: String { rawValue }
}

enum PlatformHTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

enum PlatformCredentialEncryption {
    case rsaOAEP256AESGCM
}

enum PlatformGuestAuthenticationScheme {
    case travelerV1
}

enum PlatformRequestHeaderScheme {
    case standard
    case acFanV1
}

enum PlatformSensitiveSigningScheme {
    case none
    case acFanSHA256
}

struct PlatformAccountRules {
    let accountLength: ClosedRange<Int>
    let passwordLength: ClosedRange<Int>
    let accountHint: String
    let passwordHint: String

    func accountError(_ account: String) -> String? {
        guard accountLength.contains(account.count) else {
            return "账号需为 \(accountLength.lowerBound)–\(accountLength.upperBound) 位。"
        }
        guard account.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.contains($0) && $0.isASCII
        }) else {
            return "账号只能包含英文字母和数字。"
        }
        return nil
    }

    func passwordError(_ password: String) -> String? {
        passwordLength.contains(password.count)
            ? nil
            : "密码需为 \(passwordLength.lowerBound)–\(passwordLength.upperBound) 位。"
    }
}

struct PlatformAccountAuthentication {
    let publicKeyPath: String
    let loginPath: String
    let authenticatedRegistrationPath: String
    let publicRegistrationPath: String
    let credentialEncryption: PlatformCredentialEncryption
    let rules: PlatformAccountRules
}

struct PlatformGuestAuthentication {
    let publicKeyPath: String
    let scheme: PlatformGuestAuthenticationScheme
    let loginPathPrefix: String
    let loginPathSuffix: String
    let projectType: Int

    func loginPath(key: String) -> String {
        loginPathPrefix + key + loginPathSuffix
    }
}

struct PlatformImageConfiguration {
    let xorKey: String?
    let proxyPath: String?
    let widthSuffix: String?
    let fallbackHost: String?
    let replaceableHostSuffixes: [String]
}

struct PlatformCommentCapability {
    let supportsPosting: Bool
    let requiresAccountToPost: Bool
}

struct PlatformCommunityCapability {
    let supportsFollowingFeed: Bool
    let supportsPosting: Bool
    let requiresAccountForFollowingFeed: Bool
    let requiresAccountForInteraction: Bool
}

struct PlatformLibraryCapability {
    let supportsFavorites: Bool
    let supportsHistory: Bool
    let requiresAccount: Bool
}

struct PlatformCreatorCapability {
    let supportsProfiles: Bool
    let supportsFollowing: Bool
    let requiresAccountForFollowing: Bool
}

enum PlatformHomeContentSource: Hashable {
    case stations(classifyID: String)
    case videoCatalog(classifyType: String)
}

struct PlatformHomeChannel: Identifiable, Hashable {
    let id: String
    let title: String
    let source: PlatformHomeContentSource
    let restricted: Bool
    let contentKindHint: AnimeContentKind?
}

struct PlatformRequest {
    let method: PlatformHTTPMethod
    let path: String
    let query: [String: String]
    let body: JSONObject?
    let requiresAuthentication: Bool
    let isSensitive: Bool

    init(
        method: PlatformHTTPMethod = .get,
        path: String,
        query: [String: String] = [:],
        body: JSONObject? = nil,
        requiresAuthentication: Bool = true,
        isSensitive: Bool = false
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuthentication = requiresAuthentication
        self.isSensitive = isSensitive
    }
}

protocol AnimePlatformAdapter {
    var id: AnimePlatformID { get }
    var displayName: String { get }
    var defaultBaseURL: String { get }
    var defaultAPIPrefix: String { get }
    var appVersion: String { get }
    var userMark: String { get }
    var requiresGuestSession: Bool { get }
    var requestHeaderScheme: PlatformRequestHeaderScheme { get }
    var sensitiveSigningScheme: PlatformSensitiveSigningScheme { get }
    var guestAuthentication: PlatformGuestAuthentication? { get }
    var accountAuthentication: PlatformAccountAuthentication? { get }
    var imageConfiguration: PlatformImageConfiguration { get }
    var commentCapability: PlatformCommentCapability? { get }
    var communityCapability: PlatformCommunityCapability? { get }
    var libraryCapability: PlatformLibraryCapability? { get }
    var creatorCapability: PlatformCreatorCapability? { get }
    var homeChannels: [PlatformHomeChannel] { get }

    func homeSectionsRequest(channel: PlatformHomeChannel) -> PlatformRequest?
    func homeCatalogCategoriesRequest(
        channel: PlatformHomeChannel
    ) -> PlatformRequest?
    func homeCatalogRequest(
        channel: PlatformHomeChannel,
        categoryID: String,
        pageSize: Int
    ) -> PlatformRequest?
    func homeSectionMoreRequest(
        sectionID: String,
        page: Int,
        pageSize: Int,
        sortType: Int
    ) -> PlatformRequest?
    func homeSectionChangeRequest(
        sectionID: String,
        lastItemID: String,
        pageSize: Int
    ) -> PlatformRequest?
    func categoriesRequest() -> PlatformRequest
    func catalogRequest(
        categoryID: String?,
        page: Int,
        pageSize: Int,
        sort: AnimeSort
    ) -> PlatformRequest
    func searchRequest(query: String, page: Int, pageSize: Int) -> PlatformRequest
    func searchHotWordsRequest() -> PlatformRequest?
    func detailRequest(
        itemID: String,
        contentKind: AnimeContentKind
    ) -> PlatformRequest
    func recommendationsRequest(
        itemID: String,
        contentKind: AnimeContentKind
    ) -> PlatformRequest
    func commentsRequest(
        videoID: String,
        page: Int,
        pageSize: Int,
        parentID: String?
    ) -> PlatformRequest?
    func postCommentRequest(
        videoID: String,
        content: String,
        parentID: String?,
        topID: String?
    ) -> PlatformRequest?
    func communityFeedRequest(
        scope: CommunityFeedScope,
        sort: CommunityFeedSort,
        page: Int,
        pageSize: Int
    ) -> PlatformRequest?
    func communityDetailRequest(postID: String) -> PlatformRequest?
    func communityLikeRequest(postID: String, liked: Bool) -> PlatformRequest?
    func communityCommentsRequest(
        postID: String,
        page: Int,
        pageSize: Int,
        parentID: String?
    ) -> PlatformRequest?
    func postCommunityCommentRequest(
        postID: String,
        content: String,
        parentID: String?,
        topID: String?
    ) -> PlatformRequest?
    func communityTopicsRequest() -> PlatformRequest?
    func publishCommunityPostRequest(
        content: String,
        topics: [CommunityTopic]
    ) -> PlatformRequest?
    func communityVideoPlaybackRequest(videoPath: String) -> PlatformRequest?
    func favoritesRequest(page: Int, pageSize: Int) -> PlatformRequest?
    func historyRequest(page: Int, pageSize: Int) -> PlatformRequest?
    func setFavoriteRequest(itemID: String, isFavorite: Bool) -> PlatformRequest?
    func creatorProfileRequest(userID: String) -> PlatformRequest?
    func setCreatorFollowingRequest(
        userID: String,
        isFollowing: Bool
    ) -> PlatformRequest?
    func cdnLinesRequest() -> PlatformRequest
    func playbackRequest(detail: AnimeDetail, cdnID: String?) -> PlatformRequest?
}

enum AnimePlatformRegistry {
    static let defaultID = AnimePlatformID.acFan

    static var all: [AnimePlatformAdapter] {
        [AcFanPlatformAdapter()]
    }

    static var defaultAdapter: AnimePlatformAdapter {
        adapter(for: defaultID)
    }

    static func adapter(for id: AnimePlatformID) -> AnimePlatformAdapter {
        switch id {
        case .acFan:
            return AcFanPlatformAdapter()
        }
    }
}
