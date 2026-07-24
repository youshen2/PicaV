import SwiftUI

struct CommunityPostBody: View {
    let post: CommunityPost
    var linksAreInteractive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                RemoteImageView(url: post.avatarURL, maxPixelSize: 160)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(post.author)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        if post.isFollowingAuthor {
                            Text("已关注")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.accentColor)
                        }
                    }
                    if let createdAt = post.createdAt {
                        Text(CommunityTimeFormatter.display(createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if !post.topics.isEmpty {
                Text(post.topics.prefix(3).map { "#\($0.name)" }.joined(separator: "  "))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.accentColor)
                    .lineLimit(2)
            }

            if !post.content.isEmpty {
                CommunityLinkedText(
                    content: post.content,
                    font: .body,
                    linksAreInteractive: linksAreInteractive
                )
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            CommunityImageGrid(urls: post.imageURLs)

            if post.viewCount > 0 {
                Text("\(CommunityCountFormatter.display(post.viewCount)) 次浏览")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct CommunityPostActions: View {
    let post: CommunityPost
    let onLike: () -> Void

    var body: some View {
        HStack {
            Button(action: onLike) {
                Label(
                    CommunityCountFormatter.display(post.likeCount),
                    systemImage: post.isLiked ? "heart.fill" : "heart"
                )
                .foregroundColor(post.isLiked ? .pink : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Label(
                CommunityCountFormatter.display(post.commentCount),
                systemImage: "bubble.left"
            )

            Spacer()

            Label("分享", systemImage: "arrowshape.turn.up.right")
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
}

struct CommunityCommentCard: View {
    let comment: AnimeComment
    var showsReplyPreview = true
    let onReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                RemoteImageView(url: comment.avatarURL, maxPixelSize: 128)
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(comment.author)
                        .font(.subheadline.weight(.semibold))
                    if let createdAt = comment.createdAt {
                        Text(CommunityTimeFormatter.display(createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            CommunityLinkedText(
                content: comment.content,
                font: .subheadline
            )
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let imageURL = comment.imageURL {
                RemoteImageView(
                    url: imageURL,
                    maxPixelSize: 700,
                    contentMode: .fill
                )
                    .frame(width: 220, height: 165)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 14) {
                if comment.likeCount > 0 {
                    Label(
                        CommunityCountFormatter.display(comment.likeCount),
                        systemImage: comment.isLiked ? "heart.fill" : "heart"
                    )
                }
                if comment.replyCount > 0 {
                    Label(
                        CommunityCountFormatter.display(comment.replyCount),
                        systemImage: "bubble.left"
                    )
                }
                Spacer()
                Button("回复", action: onReply)
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if showsReplyPreview, !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(comment.replies.prefix(2)) { reply in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reply.author)
                                .font(.caption.weight(.semibold))
                            CommunityLinkedText(
                                content: reply.content,
                                font: .caption
                            )
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CommunityImageGrid: View {
    let urls: [URL]

    private let itemSize: CGFloat = 92
    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: itemSize, maximum: itemSize),
                spacing: 6,
                alignment: .top
            )
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(Array(urls.prefix(9).enumerated()), id: \.offset) { _, url in
                RemoteImageView(
                    url: url,
                    maxPixelSize: 500,
                    contentMode: .fill
                )
                .frame(width: itemSize, height: itemSize)
                .clipped()
                .clipShape(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
    }
}

enum CommunityTimeFormatter {
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

enum CommunityCountFormatter {
    static func display(_ count: Int) -> String {
        switch count {
        case 10_000...:
            return String(format: "%.1f万", Double(count) / 10_000)
        case 1_000...:
            return String(format: "%.1f千", Double(count) / 1_000)
        default:
            return String(count)
        }
    }
}
