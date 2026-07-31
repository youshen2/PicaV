import SwiftUI

struct AnimeCommentsPage: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AnimeCommentsViewModel
    @State private var composeTarget: CommentComposeTarget?

    private let title: String
    private let client: AnimeAPIClient

    init(videoID: String, title: String, client: AnimeAPIClient) {
        self.title = title
        self.client = client
        _viewModel = StateObject(
            wrappedValue: AnimeCommentsViewModel(videoID: videoID, client: client)
        )
    }

    var body: some View {
        PicaNavigationContainer {
            content
                .navigationTitle("评论")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if client.supportsCommentPosting {
                            Button {
                                composeTarget = CommentComposeTarget(
                                    comment: nil,
                                    topID: nil
                                )
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .accessibilityLabel("写评论")
                        }

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("关闭")
                    }
                }
        }
        .task {
            await viewModel.load()
        }
        .sheet(item: $composeTarget) { target in
            CommentComposePage(
                animeTitle: title,
                target: target.comment,
                viewModel: viewModel
            ) { content in
                await viewModel.post(
                    content: content,
                    replyingTo: target.comment,
                    topID: target.topID
                )
            }
        }
        .alert("发送失败", isPresented: postingErrorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.postingError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("正在加载评论…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if viewModel.comments.isEmpty {
                EmptyStateView(
                    systemImage: "text.bubble",
                    title: "暂无评论",
                    message: client.supportsCommentPosting
                        ? "来留下第一条评论吧。"
                        : "当前还没有用户评论。"
                )
            } else {
                List {
                    ForEach(viewModel.comments) { comment in
                        VStack(alignment: .leading, spacing: 0) {
                            AnimeCommentRow(comment: comment) {
                                composeTarget = CommentComposeTarget(
                                    comment: comment,
                                    topID: comment.id
                                )
                            }

                            if comment.replyCount > 0 || !comment.replies.isEmpty {
                                NavigationLink {
                                    AnimeCommentThreadPage(
                                        videoID: commentVideoID,
                                        animeTitle: title,
                                        rootComment: comment,
                                        client: client,
                                        commentsViewModel: viewModel
                                    )
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(
                                            "查看全部 \(max(comment.replyCount, comment.replies.count)) 条回复"
                                        )
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.accentColor)
                                    .padding(.leading, 52)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.load(force: true)
                }
            }
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("评论加载失败")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await viewModel.load(force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var postingErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.postingError != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.postingError = nil
                }
            }
        )
    }

    private var commentVideoID: String {
        viewModel.videoID
    }
}

private struct CommentComposeTarget: Identifiable {
    let comment: AnimeComment?
    let topID: String?
    var id: String {
        "\(topID ?? "root")-\(comment?.id ?? "new-comment")"
    }
}

private struct CommentComposePage: View {
    @Environment(\.dismiss) private var dismiss
    let animeTitle: String
    let target: AnimeComment?
    @ObservedObject var viewModel: AnimeCommentsViewModel
    let onSend: (String) async -> Bool

    @State private var draft = ""

    var body: some View {
        PicaNavigationContainer {
            List {
                Section {
                    Text(animeTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    if let target {
                        Text("回复 \(target.author)：\(target.content)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }

                Section("内容") {
                    TextEditor(text: $draft)
                        .frame(minHeight: 120)
                        .disabled(viewModel.isPosting)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(target == nil ? "写评论" : "写回复")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        if await onSend(draft) {
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
            .alert("发送失败", isPresented: postingErrorPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.postingError ?? "")
            }
        }
    }

    private var postingErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.postingError != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.postingError = nil
                }
            }
        )
    }
}

private struct AnimeCommentRow: View {
    let comment: AnimeComment
    var showsReplyPreview = true
    let onReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RemoteImageView(url: comment.avatarURL, maxPixelSize: 128)
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(comment.author)
                        .font(.subheadline.weight(.semibold))
                    if let createdAt = comment.createdAt {
                        Text(CommentTimeFormatter.display(createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            Text(comment.content)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if comment.imageURL != nil {
                RemoteImageView(
                    url: comment.imageURL,
                    maxPixelSize: 800,
                    contentMode: .fill
                )
                    .frame(width: 220, height: 165)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 16) {
                if comment.likeCount > 0 {
                    Label("\(comment.likeCount)", systemImage: comment.isLiked ? "heart.fill" : "heart")
                }
                if comment.replyCount > 0 {
                    Label("\(comment.replyCount)", systemImage: "text.bubble")
                }
                Spacer()
                Button("回复", action: onReply)
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if showsReplyPreview, !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comment.replies.prefix(2)) { reply in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reply.author)
                                .font(.caption.weight(.semibold))
                            Text(reply.content)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AnimeCommentThreadPage: View {
    @StateObject private var viewModel: AnimeCommentThreadViewModel
    @ObservedObject private var commentsViewModel: AnimeCommentsViewModel
    @State private var composeTarget: CommentComposeTarget?

    private let animeTitle: String
    private let rootComment: AnimeComment

    init(
        videoID: String,
        animeTitle: String,
        rootComment: AnimeComment,
        client: AnimeAPIClient,
        commentsViewModel: AnimeCommentsViewModel
    ) {
        self.animeTitle = animeTitle
        self.rootComment = rootComment
        _commentsViewModel = ObservedObject(wrappedValue: commentsViewModel)
        _viewModel = StateObject(
            wrappedValue: AnimeCommentThreadViewModel(
                videoID: videoID,
                rootComment: rootComment,
                client: client
            )
        )
    }

    var body: some View {
        List {
            Section("原评论") {
                AnimeCommentRow(
                    comment: rootComment,
                    showsReplyPreview: false
                ) {
                    composeTarget = CommentComposeTarget(
                        comment: rootComment,
                        topID: rootComment.id
                    )
                }
            }

            Section("全部回复") {
                if viewModel.replies.isEmpty {
                    threadState
                } else {
                    ForEach(viewModel.replies) { reply in
                        AnimeCommentRow(
                            comment: reply,
                            showsReplyPreview: false
                        ) {
                            composeTarget = CommentComposeTarget(
                                comment: reply,
                                topID: rootComment.id
                            )
                        }
                        .onAppear {
                            Task {
                                await viewModel.loadMoreIfNeeded(
                                    current: reply
                                )
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let message = viewModel.loadMoreErrorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("更多回复加载失败")
                                .font(.subheadline.weight(.semibold))
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Button("重试") {
                                Task { await viewModel.retryLoadMore() }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(max(rootComment.replyCount, viewModel.replies.count)) 条回复")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(force: true)
        }
        .refreshable {
            await viewModel.load(force: true)
        }
        .sheet(item: $composeTarget) { target in
            CommentComposePage(
                animeTitle: animeTitle,
                target: target.comment,
                viewModel: commentsViewModel
            ) { content in
                let didPost = await commentsViewModel.post(
                    content: content,
                    replyingTo: target.comment,
                    topID: target.topID
                )
                if didPost {
                    await viewModel.load(force: true)
                }
                return didPost
            }
        }
    }

    @ViewBuilder
    private var threadState: some View {
        switch viewModel.state {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        case .loaded:
            Text("暂无子评论")
                .foregroundColor(.secondary)
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

private enum CommentTimeFormatter {
    static func display(_ rawValue: String) -> String {
        if let numeric = Double(rawValue) {
            let seconds = numeric > 10_000_000_000 ? numeric / 1_000 : numeric
            return relative.localizedString(
                for: Date(timeIntervalSince1970: seconds),
                relativeTo: Date()
            )
        }
        if let date = iso.date(from: rawValue) {
            return relative.localizedString(for: date, relativeTo: Date())
        }
        return rawValue
    }

    private static let iso = ISO8601DateFormatter()
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()
}
