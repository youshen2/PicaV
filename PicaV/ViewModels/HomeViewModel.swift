import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var categories: [AnimeCategory] = []
    @Published private(set) var sections: [AnimeHomeSection] = []
    @Published private(set) var popular: [Anime] = []
    @Published private(set) var latest: [Anime] = []
    @Published private(set) var channels: [PlatformHomeChannel]
    @Published private(set) var selectedChannelID: String
    @Published private(set) var shufflingSectionIDs = Set<String>()
    @Published var sectionActionErrorMessage: String?

    var hero: Anime? {
        sections.lazy.compactMap(\.items.first).first
            ?? popular.first
            ?? latest.first
    }

    var isFeaturedChannelSelected: Bool {
        selectedChannelID == channels.first?.id
    }

    init(client: AnimeAPIClient) {
        self.client = client
        let channels = client.homeChannels
        self.channels = channels
        selectedChannelID = channels.first?.id ?? ""
    }

    func load(force: Bool = false) async {
        if !force, state == .loaded { return }
        guard let channel = selectedChannel else {
            state = .failed("当前平台没有可用首页频道。")
            return
        }
        state = .loading

        var channelError: Error?
        do {
            let loadedSections = try await client.fetchHomeSections(
                channel: channel
            )
            guard selectedChannelID == channel.id else { return }
            if !loadedSections.isEmpty {
                sections = loadedSections
                categories = []
                popular = []
                latest = []
                state = .loaded
                return
            }
        } catch is CancellationError {
            return
        } catch {
            channelError = error
        }

        guard selectedChannelID == channel.id else { return }
        guard isFeaturedChannelSelected else {
            categories = []
            sections = []
            popular = []
            latest = []
            state = channelError.map {
                .failed($0.localizedDescription)
            } ?? .loaded
            return
        }

        do {
            try await loadFallbackCatalog(for: channel.id)
            guard selectedChannelID == channel.id else { return }
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            if selectedChannelID == channel.id {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func selectChannel(_ id: String) async {
        guard id != selectedChannelID,
              channels.contains(where: { $0.id == id }) else {
            return
        }
        selectedChannelID = id
        categories = []
        sections = []
        popular = []
        latest = []
        shufflingSectionIDs = []
        await load(force: true)
    }

    func shuffle(_ section: AnimeHomeSection) async {
        guard section.actions != nil,
              !shufflingSectionIDs.contains(section.id) else {
            return
        }

        let channelID = selectedChannelID
        shufflingSectionIDs.insert(section.id)
        sectionActionErrorMessage = nil
        defer { shufflingSectionIDs.remove(section.id) }

        do {
            let replacement = try await client.fetchHomeSectionReplacement(
                section: section
            )
            guard selectedChannelID == channelID,
                  let index = sections.firstIndex(where: {
                      $0.id == section.id
                  }) else {
                return
            }

            let currentIDs = Set(section.items.map(\.id))
            guard replacement.contains(where: {
                !currentIDs.contains($0.id)
            }) else {
                sectionActionErrorMessage = "这个栏目暂时没有更多内容。"
                return
            }

            sections[index] = section.replacingItems(
                Array(
                    replacement.prefix(
                        section.actions?.changePageSize
                            ?? replacement.count
                    )
                )
            )
        } catch {
            guard selectedChannelID == channelID else { return }
            sectionActionErrorMessage = error.localizedDescription
        }
    }

    private func loadFallbackCatalog(for channelID: String) async throws {
        let loadedCategories = try await client.fetchCategories()
        let categoryID = loadedCategories.first?.id
        async let popularPage = client.fetchAnime(
            categoryID: categoryID,
            page: 1,
            pageSize: 10,
            sort: .popular
        )
        async let latestPage = client.fetchAnime(
            categoryID: categoryID,
            page: 1,
            pageSize: 10,
            sort: .latest
        )

        let loadedPopular = try await popularPage.items
        let loadedLatest = try await latestPage.items
        guard selectedChannelID == channelID else { return }
        categories = loadedCategories
        sections = []
        popular = loadedPopular
        latest = loadedLatest
    }

    private let client: AnimeAPIClient

    private var selectedChannel: PlatformHomeChannel? {
        channels.first { $0.id == selectedChannelID }
    }
}
