import SwiftUI

struct HomeSectionMorePage: View {
    @StateObject private var viewModel: HomeSectionMoreViewModel

    private let section: AnimeHomeSection
    private let client: AnimeAPIClient

    init(section: AnimeHomeSection, client: AnimeAPIClient) {
        self.section = section
        self.client = client
        _viewModel = StateObject(
            wrappedValue: HomeSectionMoreViewModel(
                section: section,
                client: client
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(
                "排序",
                selection: Binding(
                    get: { viewModel.sort },
                    set: { viewModel.selectSort($0) }
                )
            ) {
                ForEach(HomeSectionSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            content
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .picaVHidesTabBar()
        .task(id: viewModel.sort) {
            await viewModel.load(force: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.state == .loading, viewModel.items.isEmpty {
            LoadStateView(state: .loading)
                .frame(maxHeight: .infinity)
        } else if case .failed = viewModel.state,
                  viewModel.items.isEmpty {
            LoadStateView(state: viewModel.state) {
                Task { await viewModel.load(force: true) }
            }
            .frame(maxHeight: .infinity)
        } else if viewModel.state == .loaded, viewModel.items.isEmpty {
            EmptyStateView(
                systemImage: "rectangle.stack",
                title: "这个栏目暂时没有内容",
                message: "可以切换排序方式，或稍后再来看看。"
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.items) { anime in
                        AnimeDetailNavigationLink(
                            anime: anime,
                            client: client
                        ) {
                            HomeSectionMoreRow(anime: anime)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreIfNeeded(
                                    currentItem: anime
                                )
                            }
                        }
                    }

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
                .padding()
            }
            .refreshable {
                await viewModel.load(force: true)
            }
        }
    }
}

private struct HomeSectionMoreRow: View {
    let anime: Anime

    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(
                urls: [anime.bannerURL, anime.coverURL],
                maxPixelSize: 620,
                contentMode: .fill
            )
            .frame(width: 132, height: 76)
            .clipped()
            .clipShape(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(anime.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if let episodeLabel = anime.episodeLabel {
                    Text(episodeLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if !anime.tags.isEmpty {
                    Text(anime.tags.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if anime.watchCount > 0 {
                    Label(
                        compactCount(anime.watchCount),
                        systemImage: "play.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}
