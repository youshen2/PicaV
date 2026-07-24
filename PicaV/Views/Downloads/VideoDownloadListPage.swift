import SwiftUI

enum VideoDownloadListScope: Equatable {
    case all
    case cached
}

struct VideoDownloadListPage: View {
    @EnvironmentObject private var downloads: VideoDownloadService
    @State private var confirmsClearCompleted = false

    let client: AnimeAPIClient
    let scope: VideoDownloadListScope

    init(
        client: AnimeAPIClient,
        scope: VideoDownloadListScope = .all
    ) {
        self.client = client
        self.scope = scope
    }

    var body: some View {
        Group {
            if visibleItemsAreEmpty {
                EmptyStateView(
                    systemImage: scope == .cached
                        ? "tray"
                        : "arrow.down.circle",
                    title: scope == .cached
                        ? "还没有已缓存视频"
                        : "还没有本地下载",
                    message: scope == .cached
                        ? "下载完成的剧集会集中显示在这里。"
                        : "在番剧详情页点按下载按钮，选择要离线观看的剧集。"
                )
            } else {
                List {
                    if scope == .all, !activeItems.isEmpty {
                        Section("下载任务") {
                            ForEach(activeItems) { item in
                                downloadLink(item)
                                    .swipeActions(edge: .leading) {
                                        controlButton(for: item)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        deleteButton(item)
                                    }
                            }
                        }
                    }

                    if !completedItems.isEmpty {
                        Section(scope == .cached ? "离线内容" : "已下载") {
                            ForEach(completedItems) { item in
                                downloadLink(item)
                                    .swipeActions(edge: .trailing) {
                                        deleteButton(item)
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(scope == .cached ? "已缓存" : "本地下载")
        .navigationBarTitleDisplayMode(.inline)
        .picaVHidesTabBar()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    confirmsClearCompleted = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(completedItems.isEmpty)
                .accessibilityLabel("清空已缓存")
            }
        }
        .alert("清空全部已缓存视频？", isPresented: $confirmsClearCompleted) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                downloads.clearCompleted()
            }
        } message: {
            Text("本地视频文件会被删除，平台收藏和浏览记录不会受到影响。")
        }
    }

    private var visibleItemsAreEmpty: Bool {
        scope == .cached
            ? completedItems.isEmpty
            : downloads.items.isEmpty
    }

    private var activeItems: [VideoDownloadItem] {
        downloads.items.filter { $0.status != .completed }
    }

    private var completedItems: [VideoDownloadItem] {
        downloads.items.filter { $0.status == .completed }
    }

    private func downloadLink(
        _ item: VideoDownloadItem
    ) -> some View {
        NavigationLink {
            AnimeDetailPage(
                videoID: item.episodeID,
                preview: item.anime,
                client: client,
                startsPlayback: true,
                initialEpisodeID: item.episodeID,
                initialEpisodeTitle: item.episodeTitle
            )
        } label: {
            VideoDownloadRow(item: item)
        }
    }

    @ViewBuilder
    private func controlButton(
        for item: VideoDownloadItem
    ) -> some View {
        switch item.status {
        case .downloading:
            Button {
                downloads.pause(item)
            } label: {
                Label("暂停", systemImage: "pause")
            }
            .tint(.orange)
        case .paused:
            Button {
                downloads.resume(item)
            } label: {
                Label("继续", systemImage: "play")
            }
            .tint(.blue)
        case .failed:
            Button {
                Task { await downloads.retry(item, client: client) }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .tint(.blue)
        case .preparing, .completed:
            EmptyView()
        }
    }

    private func deleteButton(
        _ item: VideoDownloadItem
    ) -> some View {
        Button(role: .destructive) {
            downloads.remove(item)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
}

private struct VideoDownloadRow: View {
    let item: VideoDownloadItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImageView(
                urls: [item.anime.coverURL, item.anime.bannerURL],
                maxPixelSize: 500,
                contentMode: .fill
            )
            .frame(width: 66, height: 88)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.anime.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(item.episodeTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if item.status == .downloading || item.status == .paused {
                    ProgressView(value: item.progress)
                        .tint(.accentColor)
                }

                Text(item.statusText)
                    .font(.caption)
                    .foregroundColor(
                        item.status == .failed ? .red : .secondary
                    )
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(
                systemName: item.status == .completed
                    ? "checkmark.circle.fill"
                    : statusIcon
            )
            .font(.title3)
            .foregroundColor(
                item.status == .completed ? .green : .secondary
            )
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch item.status {
        case .preparing: return "ellipsis.circle"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        }
    }
}
