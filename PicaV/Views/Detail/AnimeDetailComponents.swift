import SwiftUI

struct DetailBackdropHeader: View {
    let detail: AnimeDetail

    var body: some View {
        VStack(spacing: 0) {
            RemoteImageView(
                urls: [detail.anime.bannerURL, detail.anime.coverURL],
                maxPixelSize: 1_600
            )
            .frame(maxWidth: .infinity)
            .frame(height: 188)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.32)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            DetailIdentityHeader(detail: detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct DetailIdentityHeader: View {
    let detail: AnimeDetail

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            RemoteImageView(
                urls: [detail.anime.coverURL, detail.anime.bannerURL],
                maxPixelSize: 700
            )
            .frame(width: 96, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(detail.anime.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let episodeLabel = detail.anime.episodeLabel,
                   !episodeLabel.isEmpty {
                    Text(episodeLabel)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(detail.anime.contentKind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: Capsule()
                    )

                if !detail.anime.tags.isEmpty {
                    Text(detail.anime.tags.prefix(4).joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if detail.anime.watchCount > 0 {
                        Label(
                            compactCount(detail.anime.watchCount),
                            systemImage: "play.fill"
                        )
                    }
                    if detail.anime.likeCount > 0 {
                        Label(
                            compactCount(detail.anime.likeCount),
                            systemImage: "heart.fill"
                        )
                    }
                    if detail.anime.isPremium {
                        Label("会员", systemImage: "crown.fill")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct DetailUploaderRow: View {
    let uploader: AnimeUploader
    let canFollow: Bool
    let isUpdating: Bool
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(
                url: uploader.avatarURL,
                maxPixelSize: 192
            )
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(uploader.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text("UP主")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color.accentColor.opacity(0.12),
                            in: Capsule()
                        )
                }

                Text(displayBiography)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canFollow {
                Button(action: onFollow) {
                    Group {
                        if isUpdating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(uploader.isFollowed == true ? "已关注" : "关注")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(minWidth: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(
                    uploader.isFollowed == true
                        ? Color.secondary
                        : Color.accentColor
                )
                .disabled(isUpdating)
                .accessibilityLabel(
                    uploader.isFollowed == true ? "取消关注" : "关注上传者"
                )
            }
        }
        .padding(.vertical, 3)
    }

    private var displayBiography: String {
        let value = uploader.biography?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "这个上传者还没有留下简介" : value
    }
}

struct DetailComicChaptersSection: View {
    let detail: AnimeDetail

    private let columns = [
        GridItem(.adaptive(minimum: 82, maximum: 120), spacing: 9)
    ]

    var body: some View {
        Section {
            if detail.episodes.isEmpty {
                Text("暂未获取到章节列表")
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
                    ForEach(detail.episodes) { chapter in
                        Text(chapter.title)
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                Color(.secondarySystemFill),
                                in: RoundedRectangle(
                                    cornerRadius: 9,
                                    style: .continuous
                                )
                            )
                    }
                }
                .padding(.vertical, 3)
            }
        } header: {
            HStack {
                Text("章节")
                Spacer()
                Text("\(detail.episodes.count) 话")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } footer: {
            Text("该条目是漫画内容，因此不会请求视频播放源。")
        }
    }
}

struct DetailEpisodesSection: View {
    let detail: AnimeDetail
    let selectedEpisodeID: String?
    let onSelect: (AnimeEpisode) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 82, maximum: 120), spacing: 9)
    ]

    var body: some View {
        Section {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
                ForEach(detail.episodes) { episode in
                    Button {
                        onSelect(episode)
                    } label: {
                        Text(episode.title)
                            .font(.subheadline.weight(
                                episode.id == activeEpisodeID
                                    ? .semibold
                                    : .regular
                            ))
                            .foregroundColor(
                                episode.id == activeEpisodeID
                                    ? .white
                                    : .primary
                            )
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                episode.id == activeEpisodeID
                                    ? Color.accentColor
                                    : Color(.secondarySystemFill),
                                in: RoundedRectangle(
                                    cornerRadius: 9,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 3)
        } header: {
            HStack {
                Text("选集")
                Spacer()
                Text("\(detail.episodes.count) 集")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var activeEpisodeID: String {
        selectedEpisodeID ?? detail.currentEpisodeID
    }
}

struct DetailRecommendationRow: View {
    let anime: Anime

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImageView(
                urls: [anime.coverURL, anime.bannerURL],
                maxPixelSize: 400
            )
            .frame(width: 58, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(anime.title)
                    .font(.headline)
                    .lineLimit(2)
                if !anime.tags.isEmpty {
                    Text(anime.tags.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let episodeLabel = anime.episodeLabel {
                    Text(episodeLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

struct DetailInfoLine: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundColor(.secondary)
            Spacer(minLength: 20)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
