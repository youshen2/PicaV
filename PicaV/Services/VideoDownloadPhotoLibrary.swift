import Foundation
import Photos

enum VideoDownloadPhotoLibrary {
    static func saveVideo(at url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoDownloadPhotoLibraryError.fileMissing
        }

        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw VideoDownloadPhotoLibraryError.accessDenied
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(
                    atFileURL: url
                )
            } completionHandler: { succeeded, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if succeeded {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: VideoDownloadPhotoLibraryError.saveFailed
                    )
                }
            }
        }
    }

    private static func authorizationStatus() async
        -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private enum VideoDownloadPhotoLibraryError: LocalizedError {
    case fileMissing
    case accessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "本地 MP4 文件已不存在，请重新下载。"
        case .accessDenied:
            return "没有相册写入权限，请在系统设置中允许 PicaV 添加照片。"
        case .saveFailed:
            return "相册没有接受这个 MP4 文件。"
        }
    }
}
