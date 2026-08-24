import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var scope: AnimeSearchScope
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var results: [Anime] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreErrorMessage: String?
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
        scope = Self.savedScope(
            for: client.platformID,
            defaults: defaults
        )
        searchHistory = defaults.stringArray(
            forKey: Self.historyKey(for: client.platformID)
        ) ?? []
    }

    func queryDidChange() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != handledQuery else { return }
        handledQuery = trimmed
        debounceTask?.cancel()
        activeSearchRequestID = nil
        invalidateLoadMore()
        guard !trimmed.isEmpty else {
            state = .idle
            results = []
            hasMore = false
            loadMoreErrorMessage = nil
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
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        handledQuery = trimmed
        query = trimmed
        debounceTask?.cancel()
        await performSearch(recordsHistory: true)
    }

    func selectScope(_ newScope: AnimeSearchScope) {
        guard scope != newScope else { return }
        scope = newScope
        defaults.set(
            newScope.rawValue,
            forKey: Self.scopeKey(for: currentPlatformID)
        )
        debounceTask?.cancel()
        activeSearchRequestID = nil
        invalidateLoadMore()
        results = []
        hasMore = false
        currentPage = 1

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            return
        }
        state = .loading
        debounceTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.performSearch(recordsHistory: false)
        }
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
        scope = Self.savedScope(
            for: currentPlatformID,
            defaults: defaults
        )
        searchHistory = defaults.stringArray(
            forKey: Self.historyKey(for: currentPlatformID)
        ) ?? []
        hotWords = []
        hotWordsState = .idle
        debounceTask?.cancel()
        activeSearchRequestID = nil
        invalidateLoadMore()
        handledQuery = ""
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
        let requestedScope = scope
        let requestID = UUID()
        activeSearchRequestID = requestID
        invalidateLoadMore()
        if recordsHistory {
            recordHistory(trimmed)
        }
        state = .loading
        do {
            let page = try await client.search(
                query: trimmed,
                scope: requestedScope,
                page: 1
            )
            guard query.trimmingCharacters(in: .whitespacesAndNewlines)
                == trimmed,
                scope == requestedScope,
                activeSearchRequestID == requestID,
                !Task.isCancelled else {
                return
            }
            results = page.items.stableUniqued(id: \.id)
            currentPage = 1
            hasMore = page.hasMore
            loadMoreErrorMessage = nil
            state = .loaded
        } catch is CancellationError {
            restoreStateAfterCancellation(requestID)
        } catch {
            guard activeSearchRequestID == requestID else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current item: Anime) async {
        guard state == .loaded,
              item.id == results.last?.id,
              hasMore,
              !isLoadingMore else {
            return
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let requestedScope = scope

        let requestID = UUID()
        activeLoadMoreRequestID = requestID
        let nextPage = currentPage + 1
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer {
            if activeLoadMoreRequestID == requestID {
                isLoadingMore = false
            }
        }
        do {
            let next = try await client.search(
                query: trimmed,
                scope: requestedScope,
                page: nextPage
            )
            guard !Task.isCancelled,
                  activeLoadMoreRequestID == requestID,
                  scope == requestedScope,
                  query.trimmingCharacters(in: .whitespacesAndNewlines)
                    == trimmed else {
                return
            }
            results.append(
                contentsOf: next.items.stableUniqued(
                    seededBy: Set(results.map(\.id)),
                    id: \.id
                )
            )
            currentPage = next.page
            hasMore = next.hasMore
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadMoreRequestID == requestID else { return }
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    func retryLoadMore() async {
        guard let item = results.last else { return }
        await loadMoreIfNeeded(current: item)
    }

    private func restoreStateAfterCancellation(_ requestID: UUID) {
        guard activeSearchRequestID == requestID else { return }
        state = results.isEmpty ? .idle : .loaded
    }

    private func invalidateLoadMore() {
        activeLoadMoreRequestID = nil
        isLoadingMore = false
        loadMoreErrorMessage = nil
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

    private static func scopeKey(for platformID: AnimePlatformID) -> String {
        "search.scope.\(platformID.rawValue)"
    }

    private static func savedScope(
        for platformID: AnimePlatformID,
        defaults: UserDefaults
    ) -> AnimeSearchScope {
        defaults.string(forKey: scopeKey(for: platformID))
            .flatMap(AnimeSearchScope.init(rawValue:))
            ?? .anime
    }

    private let client: AnimeAPIClient
    private let defaults: UserDefaults
    private var currentPlatformID: AnimePlatformID
    private var currentPage = 1
    private var handledQuery = ""
    private var debounceTask: Task<Void, Never>?
    private var activeSearchRequestID: UUID?
    private var activeLoadMoreRequestID: UUID?
}
