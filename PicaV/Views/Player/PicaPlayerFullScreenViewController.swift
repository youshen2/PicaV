import UIKit

final class PicaPlayerFullScreenViewController: UIViewController {
    init(orientationMask: UIInterfaceOrientationMask) {
        self.orientationMask = orientationMask
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var orientationMask: UIInterfaceOrientationMask {
        didSet {
            if #available(iOS 16.0, *) {
                setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    override var shouldAutorotate: Bool {
        true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientationMask
    }

    override var preferredInterfaceOrientationForPresentation:
        UIInterfaceOrientation {
        if orientationMask.contains(.landscapeRight) {
            return .landscapeRight
        }
        if orientationMask.contains(.landscapeLeft) {
            return .landscapeLeft
        }
        if orientationMask.contains(.portraitUpsideDown) {
            return .portraitUpsideDown
        }
        return .portrait
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }
}
