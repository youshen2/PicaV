import KSPlayer
import UIKit

final class PicaVAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier
            == VideoDownloadService.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        VideoDownloadService.setBackgroundEventsCompletionHandler(
            completionHandler
        )
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        KSOptions.supportedInterfaceOrientations
    }
}
