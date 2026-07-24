import SwiftUI

struct CommunityDetailPage: View {
    @StateObject private var viewModel: CommunityDetailViewModel
    @State private var composeTarget: CommunityComposeTarget?

    private let client: AnimeAPIClient

    init(post: CommunityPost, client: AnimeAPIClient) {
        self.client = client
        _viewModel = StateObject(
            wrappedValue: CommunityDetailViewModel(post: post, client: client)
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                postCard
                    .padding(.horizontal, 12)

                HStack {
                    Text("评论")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Text("\(viewModel.post.commentCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                commentsContent
            }
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("动态详情")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                composeTarget = CommunityComposeTarget(
                    title: "写评论",
                    prompt: nil,
                    parentID: nil,
                    topID: nil
                )
            } label: {
                Label("留下你的评论", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.vertical, 9)
            .background(.bar)
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(force: true)
        }
        .sheet(item: $composeTarget) { target in
            CommunityCommentComposePage(
                target: target,
                viewModel: viewModel
            )
        }
        .alert("操作失败", isPresented: interactionErrorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.interactionError ?? "")
        }
    }

    private var postCard: some View {
        VStack(spacing: 12) {
            CommunityPostBody(post: viewModel.post)
            if let video = viewModel.post.video {
                CommunityVideoPlayerView(
                    postID: viewModel.post.id,
                    video: video,
                    postTitle: viewModel.post.content,
                    client: client
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            CommunityPostActions(post: viewModel.post) {
                Task { await viewModel.toggleLike() }
            }
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
    }

    @ViewBuilder
    private var commentsContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("正在加载评论…")
                .frame(maxWidth: .infinity, minHeight: 180)
        case .loaded:
            if viewModel.comments.isEmpty {
                EmptyStateView(
                    systemImage: "text.bubble",
                    title: "暂无评论",
                    message: "来留下第一条评论吧。"
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(viewModel.comments) { comment in
                    VStack(alignment: .leading, spacing: 8) {
                        CommunityCommentCard(comment: comment) {
                            composeTarget = CommunityComposeTarget(
                                title: "回复评论",
                                prompt: "回复 \(comment.author)",
                                parentID: comment.id,
                                topID: nil
                            )
                        }

                        if comment.replyCount > 0 || !comment.replies.isEmpty {
                            NavigationLink {
                                CommunityCommentThreadPage(
                                    rootComment: comment,
                                    client: client,
                                    detailViewModel: viewModel
                                )
                            } label: {
                                HStack {
                                    Text(
                                        "查看全部 \(max(comment.replyCount, comment.replies.count)) 条回复"
                                    )
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundColor(.accentColor)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .padding(.horizontal, 12)
                }
            }
        case .failed(let message):
            EmptyStateView(
                systemImage: "exclamationmark.bubble",
                title: "评论加载失败",
                message: message,
                actionTitle: "重试"
            ) {
                Task { await viewModel.load(force: true) }
            }
            .frame(maxWidth: .infinity)
        }
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

private struct CommunityCommentThreadPage: View {
    @StateObject private var viewModel: CommunityThreadViewModel
    @ObservedObject private var detailViewModel: CommunityDetailViewModel
    @State private var composeTarget: CommunityComposeTarget?

    private let rootComment: AnimeComment

    init(
        rootComment: AnimeComment,
        client: AnimeAPIClient,
        detailViewModel: CommunityDetailViewModel
    ) {
        self.rootComment = rootComment
        _detailViewModel = ObservedObject(wrappedValue: detailViewModel)
        _viewModel = StateObject(
            wrappedValue: CommunityThreadViewModel(
                postID: detailViewModel.post.id,
                rootComment: rootComment,
                client: client
            )
        )
    }

    var body: some View {
        List {
            Section("原评论") {
                CommunityCommentCard(
                    comment: rootComment,
                    showsReplyPreview: false
                ) {
                    composeTarget = CommunityComposeTarget(
                        title: "回复评论",
                        prompt: "回复 \(rootComment.author)",
                        parentID: rootComment.id,
                        topID: nil
                    )
                }
            }

            Section("全部回复") {
                switch viewModel.state {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                case .loaded:
                    if viewModel.replies.isEmpty {
                        Text("暂无子评论")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.replies) { reply in
                            CommunityCommentCard(
                                comment: reply,
                                showsReplyPreview: false
                            ) {
                                composeTarget = CommunityComposeTarget(
                                    title: "回复评论",
                                    prompt: "回复 \(reply.author)",
                                    parentID: rootComment.id,
                                    topID: reply.id
                                )
                            }
                        }
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("子评论加载失败")
                            .font(.headline)
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Button("重试") {
                            Task { await viewModel.load(force: true) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("评论回复")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(force: true)
        }
        .sheet(item: $composeTarget) { target in
            CommunityCommentComposePage(
                target: target,
                viewModel: detailViewModel
            ) {
                await viewModel.load(force: true)
            }
        }
    }
}

private struct CommunityComposeTarget: Identifiable {
    let title: String
    let prompt: String?
    let parentID: String?
    let topID: String?

    var id: String {
        "\(parentID ?? "root")-\(topID ?? "new")"
    }
}

private struct CommunityCommentComposePage: View {
    @Environment(\.dismiss) private var dismiss
    let target: CommunityComposeTarget
    @ObservedObject var viewModel: CommunityDetailViewModel
    var onPosted: (() async -> Void)?

    @State private var draft = ""

    var body: some View {
        PicaNavigationContainer {
            List {
                if let prompt = target.prompt {
                    Section {
                        Text(prompt)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Section("内容") {
                    TextEditor(text: $draft)
                        .frame(minHeight: 130)
                        .disabled(viewModel.isPosting)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        let didPost = await viewModel.postComment(
                            content: draft,
                            parentID: target.parentID,
                            topID: target.topID
                        )
                        if didPost {
                            await onPosted?()
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isPosting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("发送")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    viewModel.isPosting
                        || draft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
                .padding()
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(viewModel.isPosting)
                }
            }
        }
        .alert("发送失败", isPresented: interactionErrorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.interactionError ?? "")
        }
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
