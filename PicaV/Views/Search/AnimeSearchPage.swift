import SwiftUI

struct AnimeSearchPage: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel: SearchViewModel
    private let client: AnimeAPIClient

    init(client: AnimeAPIClient) {
        self.client = client
        _viewModel = StateObject(wrappedValue: SearchViewModel(client: client))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Picker("搜索类型", selection: scopeBinding) {
                    ForEach(AnimeSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 12)

                searchContent
                paginationContent
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("搜索")
        .searchable(
            text: $viewModel.query,
            prompt: Text(viewModel.scope.prompt)
        )
        .onChange(of: viewModel.query) { _ in
            viewModel.queryDidChange()
        }
        .onSubmit(of: .search) {
            Task { await viewModel.search() }
        }
        .task(id: settings.platformID) {
            viewModel.refreshPlatformContextIfNeeded()
            await viewModel.loadHotWords()
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch viewModel.state {
        case .idle:
            if viewModel.query.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                searchLanding
            } else {
                LoadStateView(state: .loading)
            }
        case .loading:
            LoadStateView(state: .loading)
        case .failed:
            LoadStateView(state: viewModel.state) {
                Task { await viewModel.search() }
            }
        case .loaded where viewModel.results.isEmpty:
            EmptyStateView(
                systemImage: "text.magnifyingglass",
                title: "没有搜索结果",
                message: "试试更短的关键词或其他标题。"
            )
        case .loaded:
            AnimeGridView(items: viewModel.results, client: client) { anime in
                Task { await viewModel.loadMoreIfNeeded(current: anime) }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var paginationContent: some View {
        if viewModel.isLoadingMore {
            ProgressView()
                .padding()
        } else if viewModel.loadMoreErrorMessage != nil {
            Button("重试加载更多") {
                Task { await viewModel.retryLoadMore() }
            }
            .buttonStyle(.bordered)
            .padding()
        }
    }

    private var scopeBinding: Binding<AnimeSearchScope> {
        Binding(
            get: { viewModel.scope },
            set: { viewModel.selectScope($0) }
        )
    }

    private var searchLanding: some View {
        VStack(alignment: .leading, spacing: 28) {
            hotWordsSection
            historySection

            if viewModel.hotWords.isEmpty,
               viewModel.searchHistory.isEmpty,
               viewModel.hotWordsState != .loading {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "搜索内容",
                    message: "输入片名、角色或标签，找到想看的作品。"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var hotWordsSection: some View {
        if !viewModel.hotWords.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SearchSectionHeader(
                    title: "热门搜索",
                    systemImage: "flame"
                )

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 108, maximum: 180),
                            spacing: 10
                        )
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(
                        Array(viewModel.hotWords.prefix(16).enumerated()),
                        id: \.element
                    ) { index, word in
                        Button {
                            Task { await viewModel.useSuggestion(word) }
                        } label: {
                            HStack(spacing: 7) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundColor(
                                        index < 3 ? .orange : .secondary
                                    )
                                Text(word)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 11)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 11,
                                    style: .continuous
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if viewModel.hotWordsState == .loading {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在载入热门搜索…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if case .failed = viewModel.hotWordsState {
            Button {
                Task { await viewModel.loadHotWords(force: true) }
            } label: {
                Label("热门搜索加载失败，点按重试", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !viewModel.searchHistory.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SearchSectionHeader(
                        title: "搜索历史",
                        systemImage: "clock"
                    )
                    Spacer()
                    Button("清空") {
                        viewModel.clearHistory()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(viewModel.searchHistory, id: \.self) { word in
                        HStack(spacing: 10) {
                            Button {
                                Task { await viewModel.useSuggestion(word) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(word)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                viewModel.removeHistory(word)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除 \(word)")
                        }
                        .frame(minHeight: 46)

                        if word != viewModel.searchHistory.last {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }
}

private struct SearchSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}
