import SwiftUI

struct VideoDownloadSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloads: VideoDownloadService

    let detail: AnimeDetail
    let client: AnimeAPIClient

    @State private var selectedEpisodeIDs = Set<String>()
    @State private var isSubmitting = false
    @State private var message: String?

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(episodes) { episode in
                        episodeRow(episode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggle(episode)
                            }
                    }
                } header: {
                    Text(detail.anime.title)
                } footer: {
                    Text(
                        "视频会在应用内下载并保存为 MP4；"
                            + "完成后可离线播放或导出。"
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择下载剧集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                downloadFooter
            }
            .onAppear {
                guard selectedEpisodeIDs.isEmpty,
                      let first = availableEpisodes.first else {
                    return
                }
                selectedEpisodeIDs = [first.id]
            }
        }
    }

    private var episodes: [AnimeEpisode] {
        if !detail.episodes.isEmpty {
            return detail.episodes
        }
        return [
            AnimeEpisode(
                id: detail.currentEpisodeID,
                title: "正片",
                index: 1
            )
        ]
    }

    private var availableEpisodes: [AnimeEpisode] {
        episodes.filter {
            !downloads.isUnavailableForDownload(
                platformID: client.platformID,
                animeID: detail.anime.id,
                episodeID: $0.id
            )
        }
    }

    private func episodeRow(_ episode: AnimeEpisode) -> some View {
        let item = downloads.item(
            platformID: client.platformID,
            animeID: detail.anime.id,
            episodeID: episode.id
        )
        let isUnavailable = item.map {
            [.preparing, .downloading, .paused, .completed]
                .contains($0.status)
        } ?? false
        let isSelected = selectedEpisodeIDs.contains(episode.id)

        return HStack(spacing: 12) {
            Image(
                systemName: selectionImage(
                    item: item,
                    isSelected: isSelected
                )
            )
            .font(.title3)
            .foregroundColor(
                isUnavailable ? .secondary
                    : (isSelected ? .accentColor : .secondary)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title)
                    .foregroundColor(isUnavailable ? .secondary : .primary)
                    .lineLimit(1)
                Text(item?.statusText ?? "可下载")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func selectionImage(
        item: VideoDownloadItem?,
        isSelected: Bool
    ) -> String {
        if item?.status == .completed {
            return "checkmark.circle.fill"
        }
        if item != nil, item?.status != .failed {
            return "arrow.down.circle.fill"
        }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var downloadFooter: some View {
        VStack(spacing: 10) {
            Divider()

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button {
                    selectedEpisodeIDs = Set(availableEpisodes.map(\.id))
                } label: {
                    Text("全选")
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.bordered)
                .disabled(availableEpisodes.isEmpty || isSubmitting)

                Button {
                    enqueueSelected()
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(
                            selectedEpisodeIDs.isEmpty
                                ? "开始下载"
                                : "下载 \(selectedEpisodeIDs.count) 集"
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedEpisodeIDs.isEmpty || isSubmitting)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(.regularMaterial)
    }

    private func toggle(_ episode: AnimeEpisode) {
        guard availableEpisodes.contains(where: {
            $0.id == episode.id
        }) else {
            return
        }
        if selectedEpisodeIDs.contains(episode.id) {
            selectedEpisodeIDs.remove(episode.id)
        } else {
            selectedEpisodeIDs.insert(episode.id)
        }
    }

    private func enqueueSelected() {
        let selected = episodes.filter {
            selectedEpisodeIDs.contains($0.id)
        }
        guard !selected.isEmpty else { return }

        isSubmitting = true
        message = nil
        Task {
            let count = await downloads.enqueue(
                anime: detail.anime,
                episodes: selected,
                client: client
            )
            isSubmitting = false
            if count > 0 {
                dismiss()
            } else {
                message = "选中的剧集已经下载或正在队列中。"
            }
        }
    }
}
