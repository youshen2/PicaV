import Foundation

@MainActor
extension AnimeAPIClient {
    func fetchHomeSections(
        channel: PlatformHomeChannel
    ) async throws -> [AnimeHomeSection] {
        if let request = settings.activePlatform.homeSectionsRequest(
            channel: channel
        ) {
            let payload = try await perform(request)
            let value = payload.value
            let domain = imageDomain(for: payload)
            let baseURL = settings.rootURL
            return try await mapPayload {
                AnimeMapper.homeSections(
                    from: value,
                    domain: domain,
                    baseURL: baseURL,
                    contentKindHint: channel.contentKindHint
                )
            }
        }

        guard let categoriesRequest = settings.activePlatform
            .homeCatalogCategoriesRequest(channel: channel) else {
            return []
        }
        let categoriesPayload = try await perform(categoriesRequest)
        let categoriesValue = categoriesPayload.value
        let categoriesDomain = imageDomain(for: categoriesPayload)
        let baseURL = settings.rootURL
        let categories = try await mapPayload {
            AnimeMapper.categories(
                from: categoriesValue,
                domain: categoriesDomain,
                baseURL: baseURL
            )
        }
        guard let categoryID = categories.first?.id,
              let catalogRequest = settings.activePlatform.homeCatalogRequest(
                  channel: channel,
                  categoryID: categoryID,
                  pageSize: 20
              ) else {
            return []
        }
        let catalogPayload = try await perform(catalogRequest)
        let catalogValue = catalogPayload.value
        let catalogDomain = imageDomain(for: catalogPayload)
        let items = try await mapPayload {
            AnimeMapper.animeList(
                from: catalogValue,
                domain: catalogDomain,
                baseURL: baseURL,
                contentKindHint: channel.contentKindHint
            )
        }
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
        return try await animePage(
            from: payload,
            page: page,
            pageSize: pageSize,
            contentKindHint: section.items.first?.contentKind
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
        let value = payload.value
        let domain = imageDomain(for: payload)
        let baseURL = settings.rootURL
        return try await mapPayload {
            AnimeMapper.animeList(
                from: value,
                domain: domain,
                baseURL: baseURL,
                contentKindHint: section.items.first?.contentKind
            )
        }
    }

    func fetchCategories() async throws -> [AnimeCategory] {
        let payload = try await perform(settings.activePlatform.categoriesRequest())
        let value = payload.value
        let domain = imageDomain(for: payload)
        let baseURL = settings.rootURL
        return try await mapPayload {
            AnimeMapper.categories(
                from: value,
                domain: domain,
                baseURL: baseURL
            )
        }
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
        return try await animePage(
            from: payload,
            page: page,
            pageSize: pageSize
        )
    }

    func search(
        query searchWord: String,
        scope: AnimeSearchScope,
        page: Int,
        pageSize: Int = 20
    ) async throws -> AnimePage {
        let specification = settings.activePlatform.searchRequest(
            query: searchWord,
            scope: scope,
            page: page,
            pageSize: pageSize
        )
        let payload = try await perform(specification)
        return try await animePage(
            from: payload,
            page: page,
            pageSize: pageSize,
            contentKindHint: scope.contentKind
        )
    }

    func fetchSearchHotWords() async throws -> [String] {
        guard let request = settings.activePlatform.searchHotWordsRequest() else {
            return []
        }
        let payload = try await perform(request)
        let value = payload.value
        return try await mapPayload {
            AnimeMapper.searchHotWords(from: value)
        }
    }
}
