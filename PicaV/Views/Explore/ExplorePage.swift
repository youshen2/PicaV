import SwiftUI

struct ExplorePage: View {
    @StateObject private var viewModel: CatalogViewModel
    private let client: AnimeAPIClient

    init(client: AnimeAPIClient) {
        self.client = client
        _viewModel = StateObject(
            wrappedValue: CatalogViewModel(
                client: client,
                sort: .popular,
                requiresCategory: true
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Picker("排序", selection: sortBinding) {
                    ForEach(AnimeSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if !viewModel.categories.isEmpty {
                    CategoryChips(
                        categories: viewModel.categories,
                        selectedID: viewModel.selectedCategoryID
                    ) { id in
                        Task { await viewModel.selectCategory(id) }
                    }
                }

                stateContent
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("发现")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load(force: true) }
    }

    @ViewBuilder
    private var stateContent: some View {
        if viewModel.state == .loaded, viewModel.items.isEmpty {
            EmptyStateView(
                systemImage: "sparkles.tv",
                title: "没有找到内容",
                message: "换个分类或排序方式试试。"
            )
        } else if viewModel.state == .loaded {
            AnimeGridView(items: viewModel.items, client: client) { anime in
                Task { await viewModel.loadMoreIfNeeded(current: anime) }
            }
            .padding(.horizontal)

            if viewModel.isLoadingMore {
                ProgressView()
                    .padding()
            }
        } else {
            LoadStateView(state: viewModel.state) {
                Task { await viewModel.load(force: true) }
            }
        }
    }

    private var sortBinding: Binding<AnimeSort> {
        Binding(
            get: { viewModel.sort },
            set: { value in
                Task { await viewModel.selectSort(value) }
            }
        )
    }
}
