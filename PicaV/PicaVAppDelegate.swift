import KSPlayer
import UIKit

final class PicaVAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        KSOptions.supportedInterfaceOrientations
    }
}
