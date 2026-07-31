import Combine
import Foundation

@MainActor
final class AppProxyRuntime: ObservableObject {
    enum MediaState: Equatable {
        case direct
        case starting
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var mediaState: MediaState = .direct

    var isProxyRequired: Bool {
        settings.appProxyEnabled
    }

    var mediaProxyURL: URL? {
        guard case .ready(let url) = mediaState else { return nil }
        return url
    }

    var mediaStatusText: String {
        switch mediaState {
        case .direct:
            return "直连"
        case .starting:
            return "正在启动在线播放代理…"
        case .ready:
            return "已就绪"
        case .failed(let message):
            return message
        }
    }

    init(settings: AppSettings) {
        self.settings = settings
        settingsSubscription = settings.$appProxyRevision.sink {
            [weak self] _ in
            self?.scheduleRefresh()
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh()
        }
    }

    private func refresh() async {
        do {
            switch try settings.appNetworkRoute() {
            case .direct:
                bridge.stop()
                mediaState = .direct
            case .proxy(let route):
                mediaState = .starting
                let url = try await bridge.start(route: route)
                try Task.checkCancellation()
                mediaState = .ready(url)
            }
        } catch is CancellationError {
            return
        } catch {
            bridge.stop()
            mediaState = .failed(error.localizedDescription)
        }
    }

    private let settings: AppSettings
    private let bridge = AppMediaProxyBridge()
    private var settingsSubscription: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
}
