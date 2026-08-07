import Foundation
import Network

enum VideoDownloadNetworkPolicy {
    static func validate(allowsCellular: Bool) async throws {
        guard !allowsCellular else { return }
        let path = await currentPath()
        guard path.status == .satisfied else {
            throw VideoDownloadNetworkPolicyError.offline
        }
        guard !path.usesInterfaceType(.cellular) else {
            throw VideoDownloadNetworkPolicyError.cellularDisabled
        }
    }

    private static func currentPath() async -> NWPath {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let state = PathResolutionState()
            monitor.pathUpdateHandler = { path in
                guard state.resolve() else { return }
                monitor.pathUpdateHandler = nil
                monitor.cancel()
                continuation.resume(returning: path)
            }
            monitor.start(
                queue: DispatchQueue(
                    label: "work.picav.video-downloads.network-policy"
                )
            )
        }
    }
}

private final class PathResolutionState: @unchecked Sendable {
    func resolve() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isResolved else { return false }
        isResolved = true
        return true
    }

    private let lock = NSLock()
    private var isResolved = false
}

private enum VideoDownloadNetworkPolicyError: LocalizedError {
    case offline
    case cellularDisabled

    var errorDescription: String? {
        switch self {
        case .offline:
            return "当前没有可用网络，请联网后重试。"
        case .cellularDisabled:
            return "已禁止蜂窝网络下载，请连接 Wi‑Fi 或在设置中允许蜂窝网络。"
        }
    }
}
