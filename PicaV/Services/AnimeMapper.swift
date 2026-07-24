import Foundation

enum AnimeMapper {
    static func homeSections(
        from payload: Any,
        domain: String?,
        baseURL: URL,
        contentKindHint: AnimeContentKind? = nil
    ) -> [AnimeHomeSection] {
        objects(
            from: payload,
            preferredKeys: ["data", "list", "stations", "stationList", "records"]
        )
        .enumerated()
        .compactMap { index, object in
            let items = objects(
                from: object.value(
                    for: [
                        "videoList",
                        "comicsBaseList",
                        "comicsList",
                        "videos",
                        "items",
                        "list",
                        "records"
                    ]
                ) ?? [],
                preferredKeys: [
                    "videoList",
                    "comicsBaseList",
                    "comicsList",
                    "videos",
                    "items",
                    "list",
                    "records"
                ]
            )
            .compactMap {
                anime(
                    from: $0,
                    domain: domain,
                    baseURL: baseURL,
                    contentKindHint: contentKindHint
                )
            }
            .filter { $0.contentKind != .comic }
            guard !items.isEmpty else { return nil }

            let title = object.string(
                for: ["stationName", "title", "name", "stationTitle"]
            ) ?? "推荐"
            let stationID = object.string(
                for: ["stationId", "stationID", "id"]
            )
            let identifier = stationID ?? "\(index)-\(title)"
            let layout = AnimeHomeSectionLayout(
                platformValue: object.integer(
                    for: ["type", "layoutType", "style"]
                )
            )
            return AnimeHomeSection(
                id: identifier,
                title: title,
                subtitle: object.string(
                    for: ["subtitle", "subTitle", "info", "description"]
                ),
                layout: layout,
                items: items,
                actions: stationID.map {
                    PlatformHomeSectionActions(
                        sectionID: $0,
                        sortType: object.integer(for: ["sortType"]) ?? 0,
                        changePageSize: changePageSize(for: layout)
                    )
                }
            )
        }
    }

    static func categories(from payload: Any, domain: String?, baseURL: URL) -> [AnimeCategory] {
        objects(
            from: payload,
            preferredKeys: ["list", "classTypeList", "classifyList", "records", "items"]
        ).compactMap { object in
            guard let id = object.string(for: ["classifyId", "classTypeId", "id", "typeId"]),
                  let title = object.string(for: ["classifyTitle", "classTypeTitle", "title", "name"]) else {
                return nil
            }
            let image = imageURL(
                from: object.value(
                    for: [
                        "coverImg",
                        "verticalCoverImg",
                        "coverPicture",
                        "image",
                        "icon",
                        "classifyImg"
                    ]
                ),
                domain: domain,
                baseURL: baseURL
            )
            return AnimeCategory(id: id, title: title, imageURL: image)
        }
    }

    static func animeList(
        from payload: Any,
        domain: String?,
        baseURL: URL,
        contentKindHint: AnimeContentKind? = nil
    ) -> [Anime] {
        objects(
            from: payload,
            preferredKeys: [
                "list",
                "records",
                "rows",
                "items",
                "videos",
                "videoList",
                "comicsList",
                "comicsBaseList",
                "searchList"
            ]
        ).compactMap {
            anime(
                from: $0,
                domain: domain,
                baseURL: baseURL,
                contentKindHint: contentKindHint
            )
        }
        .filter { $0.contentKind != .comic }
    }

    static func searchHotWords(from payload: Any) -> [String] {
        guard let object = payload as? JSONObject else { return [] }

        let values = [
            object.value(for: ["videoHotWordRes"]),
            object.value(for: ["hotTopicRes"])
        ]
        .compactMap { $0 }
        .flatMap {
            objects(
                from: $0,
                preferredKeys: ["list", "data", "items", "records"]
            )
        }
        .compactMap {
            $0.string(
                for: [
                    "hotTitle",
                    "searchWord",
                    "keyword",
                    "name",
                    "title"
                ]
            )
        }

        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    static func anime(
        from object: JSONObject,
        domain: String?,
        baseURL: URL,
        contentKindHint: AnimeContentKind? = nil
    ) -> Anime? {
        guard let id = object.string(
            for: ["videoId", "videoID", "animeId", "comicsId", "id"]
        ),
              let title = object.string(
                  for: [
                      "title",
                      "videoTitle",
                      "videoName",
                      "comicsTitle",
                      "name"
                  ]
              ) else {
            return nil
        }

        let vertical = imageURL(
            from: object.value(
                for: [
                    "verticalImg",
                    "verticalCoverImg",
                    "verticalCover",
                    "poster",
                    "coverPicture",
                    "comicsCover",
                    "coverImg",
                    "cover"
                ]
            ),
            domain: domain,
            baseURL: baseURL
        )
        let horizontal = imageURL(
            from: object.value(
                for: [
                    "coverImg",
                    "coverPicture",
                    "horizontalImg",
                    "banner",
                    "backImg",
                    "background",
                    "backgroundImg",
                    "bgImg",
                    "imgUrl"
                ]
            ),
            domain: domain,
            baseURL: baseURL
        )
        let price = object.double(for: ["disPrice", "price"]) ?? 0
        let tags = object.strings(for: ["tagTitles", "tags", "classifyTitles", "tagList"])
        let episodeLabel = object.string(
            for: [
                "serialTitle",
                "episodeTitle",
                "subTitle",
                "remark",
                "updateTitle",
                "episodeCount",
                "chapterNewNum",
                "chapterCount"
            ]
        )

        return Anime(
            id: id,
            title: title,
            coverURL: vertical ?? horizontal,
            bannerURL: horizontal ?? vertical,
            tags: tags,
            watchCount: object.integer(for: ["fakeWatchNum", "watchNum", "playCount", "views"]) ?? 0,
            likeCount: object.integer(for: ["fakeLikes", "likeNum", "likes"]) ?? 0,
            episodeLabel: episodeLabel,
            isPremium: price > 0
                || object.integer(for: ["videoType"]).map { [1, 2].contains($0) } == true
                || (object.boolean(for: ["isVip", "needPay"]) ?? false),
            contentKind: contentKindHint ?? contentKind(from: object)
        )
    }

    static func uploader(
        from payload: Any,
        domain: String?,
        baseURL: URL,
        fallbackID: String? = nil
    ) -> AnimeUploader? {
        guard let root = payload as? JSONObject else { return nil }
        let nested = root.object(
            for: [
                "userBase",
                "uploader",
                "userInfo",
                "author",
                "user"
            ]
        )
        let id = nested?.string(
            for: ["userId", "userID", "uid", "id"]
        )
            ?? root.string(for: ["userId", "userID", "uid", "authorId"])
            ?? fallbackID
        guard let id,
              !id.isEmpty,
              id != "0" else {
            return nil
        }

        let name = nested?.string(
            for: ["nickName", "nickname", "userName", "name"]
        )
            ?? root.string(
                for: [
                    "nickName",
                    "nickname",
                    "uploaderName",
                    "authorName",
                    "userName"
                ]
            )
            ?? "上传者"
        let avatarValue = nested?.value(
            for: ["logo", "avatar", "avatarUrl", "headImg"]
        )
            ?? root.value(
                for: [
                    "imgUrl",
                    "userLogo",
                    "avatar",
                    "avatarUrl",
                    "headImg"
                ]
            )

        return AnimeUploader(
            id: id,
            name: name,
            avatarURL: imageURL(
                from: avatarValue,
                domain: domain,
                baseURL: baseURL
            ),
            biography: nested?.string(
                for: ["personSign", "signature", "bio", "description"]
            )
                ?? root.string(
                    for: ["personSign", "signature", "bio"]
                ),
            isFollowed: root.boolean(
                for: ["attention", "isAttention", "attentionHe"]
            )
                ?? nested?.boolean(
                    for: ["attention", "isAttention", "attentionHe"]
                )
        )
    }

    static func detail(
        from payload: Any,
        domain: String?,
        baseURL: URL,
        fallbackAnime: Anime? = nil
    ) throws -> AnimeDetail {
        guard let object = detailObject(from: payload) else {
            throw AnimeAPIError.invalidPayload
        }
        let mappedAnime = anime(from: object, domain: domain, baseURL: baseURL)
        guard let anime = merged(
            detailAnime: mappedAnime,
            fallbackAnime: fallbackAnime,
            preferFallbackImages: domain == nil
        ) else {
            throw AnimeAPIError.invalidPayload
        }

        let currentID = object.string(
            for: ["videoId", "animeId", "currentChapterId", "id"]
        ) ?? anime.id
        var episodes = episodeList(
            from: object.value(
                for: [
                    "videoSerialIds",
                    "episodes",
                    "serialList",
                    "chapterList"
                ]
            )
        )
        if episodes.isEmpty, anime.contentKind.supportsPlayback {
            episodes = [AnimeEpisode(id: currentID, title: "正片", index: 1)]
        } else if anime.contentKind.supportsPlayback,
                  !episodes.contains(where: { $0.id == currentID }) {
            episodes.append(
                AnimeEpisode(id: currentID, title: "第 \(episodes.count + 1) 集", index: episodes.count + 1)
            )
        }

        let videoPath = object.string(
            for: ["videoUrl", "videoURL", "playUrl", "previewUrl", "path", "url"]
        )
            ?? object.object(for: ["cdnRes", "playInfo"])?.string(
                for: ["videoUrl", "path", "url"]
            )
        let authKey = object.string(for: ["authKey", "auth_key"])
            ?? object.object(for: ["cdnRes", "playInfo"])?.string(for: ["authKey", "auth_key"])
        let cdnID = object.string(for: ["cdnId", "cdnID"])
            ?? object.object(for: ["cdnRes", "playInfo"])?.string(for: ["id", "cdnId", "cdnID"])
        let explicitCanWatch = object.boolean(for: ["canWatch", "isCanWatch", "playable"])

        return AnimeDetail(
            anime: anime,
            synopsis: object.string(
                for: ["info", "desc", "description", "content", "introduction", "intro", "summary"]
            ) ?? "暂无剧情简介",
            episodes: episodes.sorted { $0.index < $1.index },
            currentEpisodeID: currentID,
            videoPath: videoPath,
            authKey: authKey,
            cdnID: cdnID,
            canWatch: anime.contentKind.supportsPlayback
                && (explicitCanWatch ?? (videoPath != nil)),
            releaseDate: object.string(
                for: ["createdAt", "releaseDate", "publishTime", "year"]
            ),
            isFavorite: object.boolean(for: ["favorite", "isFavorite"]),
            uploader: uploader(
                from: object,
                domain: domain,
                baseURL: baseURL,
                fallbackID: object.string(
                    for: ["userId", "userID", "uid", "authorId"]
                )
            )
        )
    }

    static func cdnLines(from payload: Any) -> [CDNLine] {
        objects(from: payload, preferredKeys: ["list", "cdnList", "lines", "items"]).compactMap { object in
            guard let id = object.string(for: ["id", "cdnId", "lineId"]) else { return nil }
            return CDNLine(
                id: id,
                name: object.string(for: ["line", "name", "title"]) ?? "线路 \(id)",
                domain: object.string(for: ["domain", "host"])
            )
        }
    }

    static func comments(from payload: Any, domain: String?, baseURL: URL) -> [AnimeComment] {
        objects(
            from: payload,
            preferredKeys: ["data", "list", "commentList", "comments", "records", "items"]
        ).compactMap {
            comment(from: $0, domain: domain, baseURL: baseURL)
        }
    }

    static func totalCount(from payload: Any) -> Int? {
        guard let object = payload as? JSONObject else { return nil }
        return object.integer(for: ["total", "totalCount", "count"])
            ?? object.object(for: ["page", "pagination"])?.integer(for: ["total", "totalCount", "count"])
    }

    private static func changePageSize(
        for layout: AnimeHomeSectionLayout
    ) -> Int {
        switch layout {
        case .landscape: return 4
        case .portrait, .portraitRail: return 6
        case .featuredLandscape: return 5
        case .compactLandscape: return 6
        }
    }

    private static func detailObject(from payload: Any, depth: Int = 0) -> JSONObject? {
        guard depth < 6 else { return nil }
        if let object = payload as? JSONObject {
            let hasIdentifier = object.string(
                for: ["videoId", "videoID", "animeId", "comicsId", "id"]
            ) != nil
            let hasTitle = object.string(
                for: ["title", "videoTitle", "videoName", "comicsTitle", "name"]
            ) != nil
            if hasIdentifier && hasTitle {
                return object
            }
            for key in [
                "data",
                "result",
                "video",
                "videoInfo",
                "videoDetail",
                "videoData",
                "detail",
                "item",
                "anime"
            ] {
                guard let nested = object[key],
                      let result = detailObject(from: nested, depth: depth + 1) else {
                    continue
                }
                return result
            }
            return nil
        }
        if let values = payload as? [Any] {
            for value in values {
                if let result = detailObject(from: value, depth: depth + 1) {
                    return result
                }
            }
        }
        return nil
    }

    private static func merged(
        detailAnime: Anime?,
        fallbackAnime: Anime?,
        preferFallbackImages: Bool
    ) -> Anime? {
        guard let detailAnime else { return fallbackAnime }
        guard let fallbackAnime else { return detailAnime }
        let detailUsesOneImage = detailAnime.coverURL == detailAnime.bannerURL
        let shouldUsePreviewCover = preferFallbackImages || detailUsesOneImage

        return Anime(
            id: detailAnime.id,
            title: detailAnime.title,
            coverURL: shouldUsePreviewCover
                ? (fallbackAnime.coverURL ?? detailAnime.coverURL)
                : (detailAnime.coverURL ?? fallbackAnime.coverURL),
            bannerURL: detailAnime.bannerURL
                ?? fallbackAnime.bannerURL
                ?? fallbackAnime.coverURL,
            tags: detailAnime.tags.isEmpty ? fallbackAnime.tags : detailAnime.tags,
            watchCount: detailAnime.watchCount > 0
                ? detailAnime.watchCount
                : fallbackAnime.watchCount,
            likeCount: detailAnime.likeCount > 0
                ? detailAnime.likeCount
                : fallbackAnime.likeCount,
            episodeLabel: detailAnime.episodeLabel ?? fallbackAnime.episodeLabel,
            isPremium: detailAnime.isPremium || fallbackAnime.isPremium,
            contentKind: detailAnime.contentKind
        )
    }

    private static func contentKind(
        from object: JSONObject
    ) -> AnimeContentKind {
        if object.string(for: ["comicsId", "comicId"]) != nil
            || object.string(for: ["comicsTitle", "comicTitle"]) != nil {
            return .comic
        }
        if object.boolean(for: ["isAnime"]) == true
            || object.integer(for: ["categoryType"]) == 3 {
            return .anime
        }
        let classifications = object.strings(
            for: ["classifyTitles", "tags", "tagTitles"]
        )
        if classifications.contains(where: {
            $0.localizedCaseInsensitiveContains("动漫")
                || $0.localizedCaseInsensitiveContains("动画")
                || $0.localizedCaseInsensitiveContains("番剧")
        }) {
            return .anime
        }
        if object.boolean(for: ["isAnime"]) == false
            || object.integer(for: ["videoMark"]) == 2 {
            return .video
        }
        return .anime
    }

    private static func objects(
        from payload: Any,
        preferredKeys: [String],
        depth: Int = 0
    ) -> [JSONObject] {
        guard depth < 4 else { return [] }
        if let objects = payload as? [JSONObject] { return objects }
        if let values = payload as? [Any] {
            return values.compactMap { $0 as? JSONObject }
        }
        guard let object = payload as? JSONObject else { return [] }

        for key in preferredKeys + ["data", "result"] {
            guard let nested = object[key] else { continue }
            let result = objects(from: nested, preferredKeys: preferredKeys, depth: depth + 1)
            if !result.isEmpty { return result }
        }
        return []
    }

    private static func episodeList(from value: Any?) -> [AnimeEpisode] {
        guard let values = value as? [Any] else { return [] }
        return values.enumerated().compactMap { offset, value in
            let index = offset + 1
            if let id = value as? String, !id.isEmpty {
                return AnimeEpisode(id: id, title: "第 \(index) 集", index: index)
            }
            if let number = value as? NSNumber {
                return AnimeEpisode(id: number.stringValue, title: "第 \(index) 集", index: index)
            }
            if let object = value as? JSONObject,
               let id = object.string(
                   for: ["videoId", "id", "episodeId", "chapterId"]
               ) {
                return AnimeEpisode(
                    id: id,
                    title: object.string(
                        for: [
                            "title",
                            "name",
                            "episodeTitle",
                            "chapterTitle"
                        ]
                    ) ?? "第 \(index) 话",
                    index: object.integer(
                        for: [
                            "index",
                            "sort",
                            "episode",
                            "chapterNum"
                        ]
                    ) ?? index
                )
            }
            return nil
        }
    }

    private static func comment(
        from object: JSONObject,
        domain: String?,
        baseURL: URL
    ) -> AnimeComment? {
        guard let id = object.string(for: ["commentId", "commentID", "id"]),
              let content = object.string(for: ["content", "comment", "text"]) else {
            return nil
        }
        let nestedReplies = (object.value(for: ["reply", "replies", "children"]) as? [Any])?
            .compactMap { $0 as? JSONObject }
            .compactMap { comment(from: $0, domain: domain, baseURL: baseURL) } ?? []
        let imageValue: Any? = {
            if let list = object.value(for: ["imageList", "images"]) {
                return list
            }
            return object.value(for: ["img", "imageUrl", "gifUrl"])
        }()

        return AnimeComment(
            id: id,
            authorID: object.string(for: ["userId", "userID", "uid"]),
            author: object.string(
                for: ["nickName", "nickname", "userName", "author", "name"]
            ) ?? "用户",
            avatarURL: imageURL(
                from: object.value(for: ["logo", "avatar", "avatarUrl", "userLogo"]),
                domain: domain,
                baseURL: baseURL
            ),
            content: content,
            createdAt: object.string(for: ["createdAt", "createTime", "time", "date"]),
            likeCount: object.integer(for: ["fakeLikes", "likeNum", "likes"]) ?? 0,
            replyCount: object.integer(for: ["replyNum", "replyCount"]) ?? nestedReplies.count,
            isLiked: object.boolean(for: ["isLike", "liked"]) ?? false,
            imageURL: imageURL(from: imageValue, domain: domain, baseURL: baseURL),
            replies: nestedReplies
        )
    }

    static func imageURL(from value: Any?, domain: String?, baseURL: URL) -> URL? {
        guard let raw = imageString(from: value) else { return nil }
        if raw.hasPrefix("//") { return URL(string: "https:\(raw)") }
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }

        let host: URL
        if let domain, !domain.isEmpty {
            let normalized = domain.contains("://") ? domain : "https://\(domain)"
            host = URL(string: normalized) ?? baseURL
        } else {
            host = baseURL
        }
        if raw.hasPrefix("/") {
            let selectedHost = raw.hasPrefix("/@/") ? baseURL : host
            let prefix = selectedHost.absoluteString.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
            return URL(string: prefix + raw)
        }
        let prefix = host.absoluteString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        return URL(
            string: prefix + "/" + raw.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        )
    }

    private static func imageString(from value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let values = value as? [Any] {
            for value in values {
                if let result = imageString(from: value) { return result }
            }
        }
        if let object = value as? JSONObject {
            return object.string(
                for: [
                    "url",
                    "path",
                    "src",
                    "image",
                    "coverImg",
                    "verticalCoverImg",
                    "coverPicture",
                    "imgUrl"
                ]
            )
        }
        return nil
    }
}
