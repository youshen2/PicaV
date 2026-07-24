import SwiftUI

struct StorageSettingsPage: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: VideoDownloadService
    @EnvironmentObject private var client: AnimeAPIClient
    @AppStorage(AnimeCacheSettingsKey.imageMaxDiskSizeMB)
    private var imageCacheLimit = AnimeImageCacheService.defaultMaxDiskSizeMB
    @AppStorage(AnimeCacheSettingsKey.detailIsEnabled)
    private var detailCacheEnabled = true
    @AppStorage(AnimeCacheSettingsKey.detailMaxDiskSizeMB)
    private var detailCacheLimit = AnimeDetailCacheService.defaultMaxDiskSizeMB

    @State private var pendingAction: DestructiveAction?
    @State private var imageCacheUsage = "计算中…"
    @State private var detailCacheUsage = "计算中…"
    @State private var completedMessage: String?

    var body: some View {
        Form {
            Section(header: Text("本机内容")) {
                SettingsValueRow(title: "收藏", value: "\(library.favorites.count) 部")
                SettingsValueRow(title: "观看历史", value: "\(library.history.count) 条")
                NavigationLink {
                    VideoDownloadListPage(client: client)
                } label: {
                    HStack {
                        Text("本地下载")
                        Spacer()
                        Text("\(downloads.items.count) 集")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(
                header: Text("图片缓存"),
                footer: Text("仅保存能够正常解码的图片，并按最近使用顺序自动清理。")
            ) {
                SettingsValueRow(title: "已使用", value: imageCacheUsage)
                Stepper(
                    "空间上限 \(imageCacheLimit) MB",
                    value: $imageCacheLimit,
                    in: 50...1_000,
                    step: 50
                )
                Button("清除图片缓存", role: .destructive) {
                    pendingAction = .imageCache
                }
            }

            Section(
                header: Text("详情缓存"),
                footer: Text("播放地址、鉴权信息和结构异常的详情不会写入缓存。")
            ) {
                Toggle("缓存番剧详情", isOn: $detailCacheEnabled)
                SettingsValueRow(title: "已使用", value: detailCacheUsage)
                Stepper(
                    "空间上限 \(detailCacheLimit) MB",
                    value: $detailCacheLimit,
                    in: 5...200,
                    step: 5
                )
                .disabled(!detailCacheEnabled)
                Button("清除详情缓存", role: .destructive) {
                    pendingAction = .detailCache
                }
            }

            Section(header: Text("管理数据")) {
                Button("清除观看历史", role: .destructive) {
                    pendingAction = .history
                }
                .disabled(library.history.isEmpty)

                Button("清除全部收藏", role: .destructive) {
                    pendingAction = .favorites
                }
                .disabled(library.favorites.isEmpty)
            }
        }
        .navigationTitle("存储与历史")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshCacheUsage()
        }
        .onChange(of: imageCacheLimit) { _ in
            AnimeImageCacheService.configure()
            Task { await refreshCacheUsage() }
        }
        .onChange(of: detailCacheLimit) { _ in
            AnimeDetailCacheService.configure()
            Task { await refreshCacheUsage() }
        }
        .onChange(of: detailCacheEnabled) { _ in
            AnimeDetailCacheService.configure()
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认清除", role: .destructive) {
                performPendingAction()
            }
            Button("取消", role: .cancel) {
                pendingAction = nil
            }
        }
        .alert(
            completedMessage ?? "",
            isPresented: Binding(
                get: { completedMessage != nil },
                set: { if !$0 { completedMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        }
    }

    private func performPendingAction() {
        switch pendingAction {
        case .imageCache:
            Task {
                await AnimeImagePipeline.shared.clear()
                await refreshCacheUsage()
                completedMessage = "图片缓存已清除"
            }
        case .detailCache:
            Task {
                await AnimeDetailCacheService.clear()
                await refreshCacheUsage()
                completedMessage = "详情缓存已清除"
            }
        case .history:
            library.clearHistory()
        case .favorites:
            library.clearFavorites()
        case .none:
            break
        }
        pendingAction = nil
    }

    private func refreshCacheUsage() async {
        async let imageUsageTask = AnimeImageCacheService.usage()
        async let detailUsageTask = AnimeDetailCacheService.usage()
        let imageUsage = await imageUsageTask
        let detailUsage = await detailUsageTask
        imageCacheUsage = AnimeImageCacheService.formattedSize(
            imageUsage.diskBytes
        )
        detailCacheUsage = AnimeImageCacheService.formattedSize(
            detailUsage.diskBytes
        )
    }
}

private enum DestructiveAction {
    case imageCache
    case detailCache
    case history
    case favorites

    var title: String {
        switch self {
        case .imageCache: return "清除全部图片缓存？"
        case .detailCache: return "清除全部详情缓存？"
        case .history: return "清除全部观看历史？"
        case .favorites: return "清除全部收藏？"
        }
    }
}
