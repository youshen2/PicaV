import Foundation

struct AcFanPlatformAdapter: AnimePlatformAdapter {
    let id = AnimePlatformID.acFan
    let displayName = "AcFan"
    let defaultBaseURL = "https://afsdas1234.5237cs3m.work"
    let defaultAPIPrefix = "/api"
    let appVersion = "1.9.6"
    let userMark = "xhp"
    let requiresGuestSession = true
    let requestHeaderScheme = PlatformRequestHeaderScheme.acFanV1
    let sensitiveSigningScheme = PlatformSensitiveSigningScheme.acFanSHA256
    let guestAuthentication: PlatformGuestAuthentication? = PlatformGuestAuthentication(
        publicKeyPath: "user/public-key/v1",
        scheme: .travelerV1,
        loginPathPrefix: "user/traveler/",
        loginPathSuffix: "/login/v1",
        projectType: 1
    )
    let accountAuthentication: PlatformAccountAuthentication? = PlatformAccountAuthentication(
        publicKeyPath: "user/public-key/v1",
        loginPath: "user/account/login/v2",
        authenticatedRegistrationPath: "user/register/v2",
        publicRegistrationPath: "user/public/register/v2",
        credentialEncryption: .rsaOAEP256AESGCM,
        rules: PlatformAccountRules(
            accountLength: 6...12,
            passwordLength: 6...20,
            accountHint: "6–12 位英文字母或数字",
            passwordHint: "6–20 位，登录密码不会保存在本机"
        )
    )
    let imageConfiguration = PlatformImageConfiguration(
        xorKey: "2020-zq3-888",
        proxyPath: "image-proxy",
        widthSuffix: "320",
        fallbackHost: "3h3ra8ruza22.xszc666.com",
        replaceableHostSuffixes: [".sayloot.com", ".pdawbdq.com", ".xszc666.com"]
    )
    let commentCapability: PlatformCommentCapability? = PlatformCommentCapability(
        supportsPosting: true,
        requiresAccountToPost: true
    )
    let communityCapability: PlatformCommunityCapability? = PlatformCommunityCapability(
        supportsFollowingFeed: true,
        supportsPosting: true,
        requiresAccountForFollowingFeed: true,
        requiresAccountForInteraction: true
    )
    let libraryCapability: PlatformLibraryCapability? = PlatformLibraryCapability(
        supportsFavorites: true,
        supportsHistory: true,
        requiresAccount: true
    )
    let creatorCapability: PlatformCreatorCapability? = PlatformCreatorCapability(
        supportsProfiles: true,
        supportsFollowing: true,
        requiresAccountForFollowing: true
    )
    let homeChannels: [PlatformHomeChannel] = [
        PlatformHomeChannel(
            id: "featured",
            title: "精选",
            source: .stations(classifyID: "4"),
            restricted: false,
            contentKindHint: nil
        ),
        PlatformHomeChannel(
            id: "anime",
            title: "动漫",
            source: .videoCatalog(classifyType: "2"),
            restricted: false,
            contentKindHint: .anime
        ),
        PlatformHomeChannel(
            id: "video",
            title: "视频",
            source: .videoCatalog(classifyType: "4"),
            restricted: false,
            contentKindHint: .video
        ),
        PlatformHomeChannel(
            id: "restricted",
            title: "里番",
            source: .stations(classifyID: "4"),
            restricted: true,
            contentKindHint: .anime
        )
    ]

    func homeSectionsRequest(
        channel: PlatformHomeChannel
    ) -> PlatformRequest? {
        guard case .stations(let classifyID) = channel.source else {
            return nil
        }
        return PlatformRequest(
            path: "station/stations",
            query: [
                "classifyId": classifyID,
                "page": "1",
                "pageSize": "30",
                "restricted": channel.restricted ? "1" : "0"
            ]
        )
    }

    func homeCatalogCategoriesRequest(
        channel: PlatformHomeChannel
    ) -> PlatformRequest? {
        guard case .videoCatalog(let classifyType) = channel.source else {
            return nil
        }
        return PlatformRequest(
            path: "video/classTypeList",
            query: [
                "type": classifyType,
                "restricted": channel.restricted ? "1" : "0"
            ]
        )
    }

    func homeCatalogRequest(
        channel: PlatformHomeChannel,
        categoryID: String,
        pageSize: Int
    ) -> PlatformRequest? {
        guard case .videoCatalog = channel.source else { return nil }
        return PlatformRequest(
            path: "video/getByClassify",
            query: [
                "classifyId": categoryID,
                "page": "1",
                "pageSize": String(pageSize),
                "sortType": "1",
                "restricted": channel.restricted ? "1" : "0"
            ]
        )
    }

    func homeSectionMoreRequest(
        sectionID: String,
        page: Int,
        pageSize: Int,
        sortType: Int
    ) -> PlatformRequest? {
        PlatformRequest(
            path: "station/getStationMore",
            query: [
                "stationId": sectionID,
                "page": String(page),
                "pageSize": String(pageSize),
                "sortType": String(sortType)
            ]
        )
    }

    func homeSectionChangeRequest(
        sectionID: String,
        lastItemID: String,
        pageSize: Int
    ) -> PlatformRequest? {
        PlatformRequest(
            path: "station/queryChange",
            query: [
                "stationId": sectionID,
                "lastId": lastItemID,
                "pageSize": String(pageSize)
            ]
        )
    }

    func categoriesRequest() -> PlatformRequest {
        PlatformRequest(
            path: "video/classTypeList",
            query: ["type": "2", "restricted": "0"]
        )
    }

    func catalogRequest(
        categoryID: String?,
        page: Int,
        pageSize: Int,
        sort: AnimeSort
    ) -> PlatformRequest {
        var query = [
            "page": String(page),
            "pageSize": String(pageSize),
            "sortType": String(sort.rawValue),
            "restricted": "0"
        ]
        if let categoryID, !categoryID.isEmpty {
            query["classifyId"] = categoryID
        }
        return PlatformRequest(path: "video/getByClassify", query: query)
    }

    func searchRequest(query: String, page: Int, pageSize: Int) -> PlatformRequest {
        PlatformRequest(
            path: "search/keyWordV2",
            query: [
                "page": String(page),
                "pageSize": String(pageSize),
                "searchType": "1",
                "searchWord": query,
                "videoMark": "2"
            ]
        )
    }

    func searchHotWordsRequest() -> PlatformRequest? {
        PlatformRequest(path: "search/hot/list")
    }

    func detailRequest(
        itemID: String,
        contentKind: AnimeContentKind
    ) -> PlatformRequest {
        if contentKind == .comic {
            return PlatformRequest(
                path: "comics/base/info",
                query: ["comicsId": itemID]
            )
        }
        return PlatformRequest(
            path: "video/getVideoById",
            query: ["videoId": itemID]
        )
    }

    func recommendationsRequest(
        itemID: String,
        contentKind: AnimeContentKind
    ) -> PlatformRequest {
        if contentKind == .comic {
            return PlatformRequest(
                path: "comics/base/getRec",
                query: ["comicsId": itemID]
            )
        }
        return PlatformRequest(
            path: "video/dataCenterMaybeLike",
            query: ["videoId": itemID]
        )
    }

    func commentsRequest(
        videoID: String,
        page: Int,
        pageSize: Int,
        parentID: String?
    ) -> PlatformRequest? {
        var query = [
            "videoId": videoID,
            "page": String(page),
            "pageSize": String(pageSize)
        ]
        if let parentID, !parentID.isEmpty {
            query["parentId"] = parentID
        }
        return PlatformRequest(path: "video/commentList", query: query)
    }

    func postCommentRequest(
        videoID: String,
        content: String,
        parentID: String?,
        topID: String?
    ) -> PlatformRequest? {
        var body: JSONObject = [
            "videoId": videoID,
            "content": content
        ]
        if let parentID, !parentID.isEmpty {
            body["parentId"] = parentID
        }
        if let topID, !topID.isEmpty {
            body["topId"] = topID
        }
        return PlatformRequest(
            method: .post,
            path: "video/saveComment",
            body: body
        )
    }

    func communityFeedRequest(
        scope: CommunityFeedScope,
        sort: CommunityFeedSort,
        page: Int,
        pageSize: Int
    ) -> PlatformRequest? {
        let path = scope == .following
            ? "community/dynamic/dynamicAttentionList"
            : "community/dynamic/list"
        return PlatformRequest(
            path: path,
            query: [
                "page": String(page),
                "pageSize": String(pageSize),
                "loadType": String(sort.rawValue)
            ]
        )
    }

    func communityDetailRequest(postID: String) -> PlatformRequest? {
        PlatformRequest(
            path: "community/dynamic/dynamicInfo",
            query: ["dynamicId": postID]
        )
    }

    func communityLikeRequest(postID: String, liked: Bool) -> PlatformRequest? {
        PlatformRequest(
            method: .post,
            path: liked
                ? "community/dynamic/like"
                : "community/dynamic/unLike",
            body: ["dynamicId": postID]
        )
    }

    func communityCommentsRequest(
        postID: String,
        page: Int,
        pageSize: Int,
        parentID: String?
    ) -> PlatformRequest? {
        var query = [
            "dynamicId": postID,
            "page": String(page),
            "pageSize": String(pageSize)
        ]
        if let parentID, !parentID.isEmpty {
            query["parentId"] = parentID
        }
        return PlatformRequest(
            path: "community/dynamic/commentList",
            query: query
        )
    }

    func postCommunityCommentRequest(
        postID: String,
        content: String,
        parentID: String?,
        topID: String?
    ) -> PlatformRequest? {
        var body: JSONObject = [
            "dynamicId": postID,
            "content": content
        ]
        if let parentID, !parentID.isEmpty {
            body["parentId"] = parentID
        }
        if let topID, !topID.isEmpty {
            body["topId"] = topID
        }
        return PlatformRequest(
            method: .post,
            path: "community/dynamic/saveComment",
            body: body
        )
    }

    func communityTopicsRequest() -> PlatformRequest? {
        PlatformRequest(
            path: "coterie/list",
            query: ["isAll": "true"]
        )
    }

    func publishCommunityPostRequest(
        content: String,
        topics: [CommunityTopic]
    ) -> PlatformRequest? {
        PlatformRequest(
            method: .post,
            path: "community/dynamic/release",
            body: [
                "content": content,
                "coteries": topics.map(\.platformObject),
                "dynamicImg": [],
                "dynamicType": 1,
                "secret": false,
                "price": 0
            ]
        )
    }

    func communityVideoPlaybackRequest(videoPath: String) -> PlatformRequest? {
        guard !videoPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return nil
        }
        return PlatformRequest(
            path: "m3u8/h5/decode",
            query: ["path": videoPath]
        )
    }

    func favoritesRequest(page: Int, pageSize: Int) -> PlatformRequest? {
        PlatformRequest(
            path: "video/likeList",
            query: [
                "page": String(page),
                "pageSize": String(pageSize)
            ]
        )
    }

    func historyRequest(page: Int, pageSize: Int) -> PlatformRequest? {
        PlatformRequest(
            path: "userBrowse/list",
            query: [
                "page": String(page),
                "pageSize": String(pageSize),
                "type": "1"
            ]
        )
    }

    func setFavoriteRequest(
        itemID: String,
        isFavorite: Bool
    ) -> PlatformRequest? {
        PlatformRequest(
            method: .post,
            path: isFavorite
                ? "video/favoritesVideo"
                : "video/cancelVideoFavorites",
            body: ["videoId": itemID]
        )
    }

    func creatorProfileRequest(userID: String) -> PlatformRequest? {
        PlatformRequest(
            path: "im/user/baseUserInfo",
            query: ["userId": userID]
        )
    }

    func setCreatorFollowingRequest(
        userID: String,
        isFollowing: Bool
    ) -> PlatformRequest? {
        PlatformRequest(
            method: .post,
            path: isFollowing
                ? "userAttention/attention"
                : "userAttention/attention/cancel",
            body: ["toUserId": userID]
        )
    }

    func cdnLinesRequest() -> PlatformRequest {
        PlatformRequest(path: "video/cdn/cdnList")
    }

    func playbackRequest(detail: AnimeDetail, cdnID: String?) -> PlatformRequest? {
        guard detail.canWatch, let path = detail.videoPath, !path.isEmpty else { return nil }
        if let authKey = detail.authKey, !authKey.isEmpty {
            var query = ["path": path, "auth_key": authKey]
            if let cdnID, !cdnID.isEmpty { query["id"] = cdnID }
            return PlatformRequest(path: "m3u8/decode/authPath", query: query)
        }
        return PlatformRequest(path: "m3u8/h5/decode", query: ["path": path])
    }
}

