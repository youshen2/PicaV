import SwiftUI

struct AnimeCardView: View {
    let anime: Anime
    var fillsAvailableWidth = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sizedCover

            Text(anime.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, titleTopSpacing)

            if !anime.tags.isEmpty {
                Text(anime.tags.prefix(2).joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, 6)
            } else if anime.watchCount > 0 {
                Label(compactCount(anime.watchCount), systemImage: "play.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
            }
        }
        .frame(
            width: coverWidth,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }

    private var sizedCover: some View {
        RemoteImageView(
            url: anime.coverURL,
            maxPixelSize: 640,
            contentMode: .fill
        )
        .frame(width: coverWidth, height: coverHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if let episode = anime.episodeLabel {
                Text(episode)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(7)
            }
        }
        .overlay(alignment: .topTrailing) {
            if anime.isPremium {
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .padding(7)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
                    .padding(7)
            }
        }
    }

    private var coverWidth: CGFloat {
        fillsAvailableWidth
            ? AnimeCardMetrics.gridWidth
            : AnimeCardMetrics.width
    }

    private var coverHeight: CGFloat {
        fillsAvailableWidth
            ? AnimeCardMetrics.gridHeight
            : AnimeCardMetrics.height
    }

    private var titleTopSpacing: CGFloat {
        fillsAvailableWidth ? 8 : 12
    }
}

struct AnimeGridView: View {
    let items: [Anime]
    let client: AnimeAPIClient
    var onItemAppear: ((Anime) -> Void)?

    private let columns = [
        GridItem(
            .adaptive(
                minimum: AnimeCardMetrics.gridWidth,
                maximum: AnimeCardMetrics.gridWidth
            ),
            spacing: AnimeCardMetrics.gridSpacing,
            alignment: .top
        )
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
            ForEach(items) { anime in
                AnimeDetailNavigationLink(anime: anime, client: client) {
                    AnimeCardView(
                        anime: anime,
                        fillsAvailableWidth: true
                    )
                }
                .buttonStyle(.plain)
                .onAppear {
                    onItemAppear?(anime)
                }
            }
        }
    }
}

enum AnimeCardMetrics {
    static let width: CGFloat = 150
    static let height: CGFloat = 200
    static let gridWidth: CGFloat = 108
    static let gridHeight: CGFloat = 144
    static let gridSpacing: CGFloat = 8
}

struct AnimeRowView: View {
    let anime: Anime

    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(url: anime.coverURL, maxPixelSize: 360)
                .frame(width: 76, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 7) {
                Text(anime.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if !anime.tags.isEmpty {
                    Text(anime.tags.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if anime.watchCount > 0 {
                    Label(compactCount(anime.watchCount), systemImage: "play.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

func compactCount(_ value: Int) -> String {
    if value >= 100_000_000 {
        return String(format: "%.1f亿", Double(value) / 100_000_000)
    }
    if value >= 10_000 {
        return String(format: "%.1f万", Double(value) / 10_000)
    }
    return String(value)
}
