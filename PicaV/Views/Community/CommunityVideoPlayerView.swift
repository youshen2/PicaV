import Combine
import SwiftUI

struct CommunityVideoPlayerView: View {
    @ObservedObject private var coordinator = CommunityPlaybackCoordinator.shared
    @State private var playbackURL: URL?
    @State private var hasStarted = false
    @State private var isVisible = false
    @State private var errorMessage: String?

    let postID: String
    let video: CommunityVideo
    let postTitle: String
    let client: AnimeAPIClient

    var body: some View {
        ZStack {
            Color.black

            if hasStarted, let playbackURL {
                KSPlayerContainerView(
                    sources: [
                        PlaybackSource(
                            id: "community-\(postID)",
                            name: "默认线路",
                            url: playbackURL
                        )
                    ],
                    title: video.title ?? postTitle,
                    initialSourceIndex: 0,
                    resumeTime: 0,
                    isActive: isVisible && coordinator.activePostID == postID,
                    onProgress: { _, _ in },
                    onPlaybackEnded: {},
                    onSourceChange: { _ in }
                )
            } else {
                RemoteImageView(
                    url: video.coverURL,
                    maxPixelSize: 900,
                    contentMode: .fill
                )
                .frame(width: 260, height: 146)
                .clipped()

                Color.black.opacity(video.coverURL == nil ? 0.2 : 0.28)

                Button {
                    startPlayback()
                } label: {
                    Image(systemName: video.isLocked ? "lock.fill" : "play.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 58, height: 58)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(video.isLocked ? "付费视频" : "播放社区视频")
            }
        }
        .frame(width: 260, height: 146)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
            if coordinator.activePostID == postID {
                coordinator.activePostID = nil
            }
            hasStarted = false
            playbackURL = nil
        }
        .alert("无法播放", isPresented: errorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startPlayback() {
        guard !video.isLocked else {
            errorMessage = "这是付费社区视频，请先在平台解锁后播放。"
            return
        }
        do {
            playbackURL = try client.communityPlaybackURL(for: video)
            hasStarted = true
            coordinator.activePostID = postID
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { presented in
                if !presented {
                    errorMessage = nil
                }
            }
        )
    }
}

private final class CommunityPlaybackCoordinator: ObservableObject {
    static let shared = CommunityPlaybackCoordinator()

    @Published var activePostID: String?

    private init() {}
}
