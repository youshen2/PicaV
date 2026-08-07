import SwiftUI

struct CommunityPage: View {
    @StateObject private var viewModel: CommunityViewModel
    @State private var showsComposer = false

    private let client: AnimeAPIClient

    init(client: AnimeAPIClient) {
        self.client = client
        _viewModel = StateObject(
            wrappedValue: CommunityViewModel(client: client)
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                controls
                stateContent
            }
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("社区")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showsComposer = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(!client.supportsCommunityPublishing)
                .opacity(client.supportsCommunityPublishing ? 1 : 0)
                .accessibilityLabel("发布动态")
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(force: true)
        }
        .sheet(isPresented: $showsComposer, onDismiss: {
            Task { await viewModel.load(force: true) }
        }) {
            CommunityComposePage(client: client)
        }
        .alert("操作失败", isPresented: interactionErrorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.interactionError ?? "")
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("动态范围", selection: scopeBinding) {
                Text(CommunityFeedScope.publicFeed.title)
                    .tag(CommunityFeedScope.publicFeed)
                if client.supportsCommunityFollowingFeed {
                    Text(CommunityFeedScope.following.title)
                        .tag(CommunityFeedScope.following)
                }
            }
            .pickerStyle(.segmented)

            Picker("动态排序", selection: sortBinding) {
                ForEach(CommunityFeedSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var stateContent: some View {
        if !client.supportsCommunity {
            EmptyStateView(
                systemImage: "person.3",
                title: "当前平台没有社区",
                message: "切换到支持社区的平台后即可查看。"
            )
        } else if viewModel.scope == .following,
                  client.communityFollowingFeedRequiresAccount,
                  !client.isAccountLoggedIn {
            VStack(spacing: 6) {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    title: "登录后查看关注动态",
                    message: "关注流与当前平台账号同步。"
                )
                NavigationLink {
                    AccountAuthenticationPage(action: .login)
                        .picaVHidesTabBar()
                } label: {
                    Text("登录平台账号")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 28)
        } else {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("正在加载社区…")
                    .frame(maxWidth: .infinity, minHeight: 260)
            case .loaded:
                if viewModel.posts.isEmpty {
                    EmptyStateView(
                        systemImage: viewModel.scope == .following
                            ? "person.2.slash"
                            : "text.bubble",
                        title: viewModel.scope == .following ? "暂无关注动态" : "暂无动态",
                        message: viewModel.scope == .following
                            ? "关注创作者后，他们的新动态会出现在这里。"
                            : "稍后再来看看，或发布第一条动态。"
                    )
                } else {
                    ForEach(viewModel.posts) { post in
                        CommunityFeedCard(
                            post: post,
                            client: client
                        ) {
                            Task { await viewModel.toggleLike(postID: post.id) }
                        }
                        .padding(.horizontal, 12)
                        .onAppear {
                            Task {
                                await viewModel.loadMoreIfNeeded(current: post)
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
            case .failed(let message):
                EmptyStateView(
                    systemImage: "wifi.exclamationmark",
                    title: "社区加载失败",
                    message: message,
                    actionTitle: "重试"
                ) {
                    Task { await viewModel.load(force: true) }
                }
            }
        }
    }

    private var scopeBinding: Binding<CommunityFeedScope> {
        Binding(
            get: { viewModel.scope },
            set: { value in
                viewModel.selectScope(value)
            }
        )
    }

    private var sortBinding: Binding<CommunityFeedSort> {
        Binding(
            get: { viewModel.sort },
            set: { value in
                viewModel.selectSort(value)
            }
        )
    }

    private var interactionErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.interactionError != nil },
            set: { presented in
                if !presented {
                    viewModel.interactionError = nil
                }
            }
        )
    }
}

private struct CommunityFeedCard: View {
    let post: CommunityPost
    let client: AnimeAPIClient
    let onLike: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            NavigationLink {
                CommunityDetailPage(post: post, client: client)
                    .picaVHidesTabBar()
            } label: {
                CommunityPostSummary(
                    post: post,
                    linksAreInteractive: false
                )
            }
            .buttonStyle(.plain)

            if !post.imageURLs.isEmpty {
                CommunityImageGrid(urls: post.imageURLs)
            }

            if post.viewCount > 0 {
                CommunityPostViewCount(viewCount: post.viewCount)
            }

            if let video = post.video {
                CommunityVideoPlayerView(
                    postID: post.id,
                    video: video,
                    postTitle: post.content,
                    client: client
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            CommunityPostActions(post: post, onLike: onLike)
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
    }
}
