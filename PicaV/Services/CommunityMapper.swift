import Foundation

enum CommunityMapper {
    static func posts(
        from payload: Any,
        domain: String?,
        baseURL: URL
    ) -> [CommunityPost] {
        objects(
            from: payload,
            preferredKeys: ["data", "list", "records", "items", "dynamicList"]
        ).compactMap {
            post(from: $0, domain: domain, baseURL: baseURL)
        }
    }

    static func post(
        from payload: Any,
        domain: String?,
        baseURL: URL
    ) -> CommunityPost? {
        guard let object = detailObject(from: payload) else { return nil }
        return post(from: object, domain: domain, baseURL: baseURL)
    }

    static func topics(from payload: Any) -> [CommunityTopic] {
        objects(
            from: payload,
            preferredKeys: ["data", "list", "records", "items", "coteries"]
        )
        .compactMap { object in
            guard let name = object.string(
                for: ["name", "title", "coterieName", "topicName"]
            ) else {
                return nil
            }
            return CommunityTopic(
                id: object.string(for: ["id", "coterieId", "topicId"]),
                name: name
            )
        }
        .uniqued(by: \.name)
    }

    private static func post(
        from object: JSONObject,
        domain: String?,
        baseURL: URL
    ) -> CommunityPost? {
        guard let id = object.string(
            for: ["dynamicId", "dynamicID", "postId", "id"]
        ) else {
            return nil
        }

        let videoObject = object.object(for: ["video"])
        let video: CommunityVideo? = {
            guard let videoObject,
                  let path = videoObject.string(
                      for: ["videoUrl", "videoURL", "path", "url"]
                  ) else {
                return nil
            }
            let price = object.double(for: ["price", "gold"]) ?? 0
            let isUnlocked = object.boolean(for: ["isUnlock", "unlocked"]) ?? false
            return CommunityVideo(
                path: path,
                coverURL: AnimeMapper.imageURL(
                    from: videoObject.value(
                        for: ["coverImg", "cover", "poster"]
                    ),
                    domain: domain,
                    baseURL: baseURL
                ),
                title: videoObject.string(
                    for: ["title", "videoTitle", "comicsTitle", "name"]
                ),
                width: videoObject.integer(for: ["width", "videoWidth"]),
                height: videoObject.integer(for: ["height", "videoHeight"]),
                isLocked: price > 0 && !isUnlocked
            )
        }()
        let images = imageValues(from: object)
            .compactMap {
                AnimeMapper.imageURL(from: $0, domain: domain, baseURL: baseURL)
            }
            .uniqued(by: \.absoluteString)
        let topics: [CommunityTopic] = (
            (object.value(for: ["coteries", "topics", "topicList"]) as? [Any])
                ?? []
        ).compactMap { value in
                guard let topic = value as? JSONObject,
                      let name = topic.string(for: ["name", "title"]) else {
                    return nil
                }
                return CommunityTopic(
                    id: topic.string(for: ["id", "topicId", "coterieId"]),
                    name: name
                )
            }

        return CommunityPost(
            id: id,
            authorID: object.string(for: ["userId", "userID", "uid"]),
            author: object.string(
                for: ["nickName", "nickname", "userName", "author", "name"]
            ) ?? "用户",
            avatarURL: AnimeMapper.imageURL(
                from: object.value(for: ["logo", "avatar", "avatarUrl", "userLogo"]),
                domain: domain,
                baseURL: baseURL
            ),
            content: object.string(for: ["content", "text", "description"]) ?? "",
            createdAt: object.string(
                for: ["checkAt", "createdAt", "createTime", "publishTime", "time"]
            ),
            imageURLs: images,
            video: video,
            topics: topics,
            viewCount: object.integer(for: ["lookedNum", "viewCount", "views"]) ?? 0,
            likeCount: object.integer(for: ["fakeLikes", "likeNum", "likes"]) ?? 0,
            commentCount: object.integer(for: ["commentNum", "commentCount"]) ?? 0,
            isLiked: object.boolean(for: ["isLike", "liked"]) ?? false,
            isFollowingAuthor: object.boolean(
                for: ["isAttention", "isFollowing", "followed"]
            ) ?? false
        )
    }

    private static func imageValues(from object: JSONObject) -> [Any] {
        var values: [Any] = []
        if let images = object.value(for: ["dynamicImg", "imageList", "images"]) as? [Any] {
            values.append(contentsOf: images)
        } else if let image = object.value(for: ["dynamicImg", "image", "cover"]) {
            values.append(image)
        }
        return values
    }

    private static func detailObject(from payload: Any, depth: Int = 0) -> JSONObject? {
        guard depth < 6 else { return nil }
        if let object = payload as? JSONObject {
            if object.string(for: ["dynamicId", "dynamicID", "postId"]) != nil {
                return object
            }
            for key in ["data", "result", "detail", "dynamic", "item"] {
                guard let nested = object[key],
                      let result = detailObject(from: nested, depth: depth + 1) else {
                    continue
                }
                return result
            }
        }
        return nil
    }

    private static func objects(
        from payload: Any,
        preferredKeys: [String],
        depth: Int = 0
    ) -> [JSONObject] {
        guard depth < 5 else { return [] }
        if let objects = payload as? [JSONObject] { return objects }
        if let values = payload as? [Any] {
            return values.compactMap { $0 as? JSONObject }
        }
        guard let object = payload as? JSONObject else { return [] }
        for key in preferredKeys + ["data", "result"] {
            guard let nested = object[key] else { continue }
            let result = objects(
                from: nested,
                preferredKeys: preferredKeys,
                depth: depth + 1
            )
            if !result.isEmpty { return result }
        }
        return []
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
