import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var results: [Anime] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hotWords: [String] = []
    @Published private(set) var hotWordsState: LoadState = .idle
    @Published private(set) var searchHistory: [String]

    init(
        client: AnimeAPIClient,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
        currentPlatformID = client.platformID
        searchHistory = defaults.stringArray(
            forKey: Self.historyKey(for: client.platformID)
        ) ?? []
    }

    func queryDidChange() {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            results = []
            hasMore = false
            return
        }

        state = .loading
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSearch(recordsHistory: false)
        }
    }

    func search() async {
        debounceTask?.cancel()
        await performSearch(recordsHistory: true)
    }

    func useSuggestion(_ word: String) async {
        query = word
        debounceTask?.cancel()
        await performSearch(recordsHistory: true)
    }

    func loadHotWords(force: Bool = false) async {
        refreshPlatformContextIfNeeded()
        guard force || hotWordsState == .idle else { return }

        hotWordsState = .loading
        do {
            hotWords = try await client.fetchSearchHotWords()
            hotWordsState = .loaded
        } catch is CancellationError {
            return
        } catch {
            hotWordsState = .failed(error.localizedDescription)
        }
    }

    func removeHistory(_ word: String) {
        searchHistory.removeAll { $0 == word }
        saveHistory()
    }

    func clearHistory() {
        searchHistory = []
        saveHistory()
    }

    func refreshPlatformContextIfNeeded() {
        guard currentPlatformID != client.platformID else { return }
        currentPlatformID = client.platformID
        searchHistory = defaults.stringArray(
            forKey: Self.historyKey(for: currentPlatformID)
        ) ?? []
        hotWords = []
        hotWordsState = .idle
        query = ""
        results = []
        state = .idle
        hasMore = false
        currentPage = 1
    }

    private func performSearch(recordsHistory: Bool) async {
        refreshPlatformContextIfNeeded()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if recordsHistory {
            recordHistory(trimmed)
        }
        state = .loading
        do {
            let page = try await client.search(query: trimmed, page: 1)
            guard query.trimmingCharacters(in: .whitespacesAndNewlines)
                == trimmed else {
                return
            }
            results = page.items
            currentPage = 1
            hasMore = page.hasMore
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current item: Anime) async {
        guard item.id == results.last?.id, hasMore, !isLoadingMore else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await client.search(query: trimmed, page: currentPage + 1)
            let existing = Set(results.map(\.id))
            results.append(contentsOf: next.items.filter { !existing.contains($0.id) })
            currentPage = next.page
            hasMore = next.hasMore
        } catch {
            hasMore = false
        }
    }

    private func recordHistory(_ word: String) {
        searchHistory.removeAll {
            $0.compare(word, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
        }
        searchHistory.insert(word, at: 0)
        searchHistory = Array(searchHistory.prefix(20))
        saveHistory()
    }

    private func saveHistory() {
        defaults.set(
            searchHistory,
            forKey: Self.historyKey(for: currentPlatformID)
        )
    }

    private static func historyKey(for platformID: AnimePlatformID) -> String {
        "search.history.\(platformID.rawValue)"
    }

    private let client: AnimeAPIClient
    private let defaults: UserDefaults
    private var currentPlatformID: AnimePlatformID
    private var currentPage = 1
    private var debounceTask: Task<Void, Never>?
}
