import AVFoundation
import KSPlayer
import SwiftUI

struct KSPlayerContainerView: UIViewRepresentable {
    let sources: [PlaybackSource]
    let title: String
    let initialSourceIndex: Int
    let resumeTime: TimeInterval
    let isActive: Bool
    let onProgress: (TimeInterval, TimeInterval) -> Void
    let onSourceChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onProgress: onProgress,
            onSourceChange: onSourceChange
        )
    }

    func makeUIView(context: Context) -> PicaPlayerHostView {
        let hostView = PicaPlayerHostView()
        let view = hostView.playerView
        view.backgroundColor = .black
        view.toolBar.definitionButton.accessibilityLabel = "播放线路"
        context.coordinator.attach(to: view)
        configure(view, coordinator: context.coordinator)
        return hostView
    }

    func updateUIView(_ hostView: PicaPlayerHostView, context: Context) {
        context.coordinator.onProgress = onProgress
        context.coordinator.onSourceChange = onSourceChange
        configure(hostView.playerView, coordinator: context.coordinator)
    }

    static func dismantleUIView(
        _ hostView: PicaPlayerHostView,
        coordinator: Coordinator
    ) {
        let view = hostView.playerView
        if view.landscapeButton.isSelected {
            view.updateUI(isFullScreen: false)
        }
        view.pause()
        view.resetPlayer()
        coordinator.resourceSignature = nil
    }

    private func configure(_ view: PicaKSPlayerView, coordinator: Coordinator) {
        let signature = sources
            .map { "\($0.id):\($0.url.absoluteString)" }
            .joined(separator: "|")
        if coordinator.resourceSignature != signature {
            coordinator.resourceSignature = signature

            let definitions = sources.map { source -> KSPlayerResourceDefinition in
                let options = KSOptions()
                options.startPlayTime = resumeTime
                options.isAccurateSeek = false
                options.isSeekedAutoPlay = true
                options.preferredForwardBufferDuration = 1.5
                return KSPlayerResourceDefinition(
                    url: source.url,
                    definition: source.name,
                    options: options
                )
            }
            let resource = KSPlayerResource(
                name: title,
                definitions: definitions
            )
            view.set(
                resource: resource,
                definitionIndex: min(
                    max(initialSourceIndex, 0),
                    definitions.count - 1
                )
            )
        }

        if isActive {
            if coordinator.wasActive == false {
                view.play()
            }
        } else {
            view.pause()
        }
        coordinator.wasActive = isActive
    }

    final class Coordinator {
        var onProgress: (TimeInterval, TimeInterval) -> Void
        var onSourceChange: (Int) -> Void
        var resourceSignature: String?
        var wasActive: Bool?

        init(
            onProgress: @escaping (TimeInterval, TimeInterval) -> Void,
            onSourceChange: @escaping (Int) -> Void
        ) {
            self.onProgress = onProgress
            self.onSourceChange = onSourceChange
        }

        func attach(to view: PicaKSPlayerView) {
            view.playTimeDidChange = { [weak self] currentTime, totalTime in
                self?.onProgress(currentTime, totalTime)
            }
            view.sourceDidChange = { [weak self] index in
                self?.onSourceChange(index)
            }
            view.backBlock = {}
        }
    }
}

final class PicaPlayerHostView: UIView {
    let playerView = PicaKSPlayerView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true

        addSubview(playerView)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard playerView.superview === self else { return }
        playerView.setNeedsLayout()
        playerView.playerLayer?.player.view?.setNeedsLayout()
    }
}

final class PicaKSPlayerView: IOSVideoPlayerView {
    var sourceDidChange: ((Int) -> Void)?

    override func player(layer: KSPlayerLayer, state: KSPlayerState) {
        super.player(layer: layer, state: state)
        if state == .readyToPlay {
            installPlaybackRateMenu()
        }
    }

    override func updateUI(isFullScreen: Bool) {
        super.updateUI(isFullScreen: isFullScreen)
        let delay: TimeInterval = isFullScreen ? 0.15 : 0.45
        if isFullScreen {
            requestOrientation(.landscapeRight)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.requestOrientation(
                isFullScreen ? .landscapeRight : .portrait
            )
            self.superview?.setNeedsLayout()
            self.superview?.layoutIfNeeded()
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.playerLayer?.player.view?.setNeedsLayout()
            if !isFullScreen, self.playerLayer?.state.isPlaying == true {
                self.play()
            }
        }
    }

    override func change(definitionIndex: Int) {
        super.change(definitionIndex: definitionIndex)
        sourceDidChange?(definitionIndex)
    }

    override func seek(
        time: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        guard let playerLayer,
              playerLayer.url.isFileURL,
              let localPlayer = playerLayer.player as? KSAVPlayer else {
            super.seek(time: time, completion: completion)
            return
        }

        let targetTime = Self.localSeekTime(
            requestedTime: time,
            duration: localPlayer.duration
        )
        let target = CMTime(
            seconds: targetTime,
            preferredTimescale: 600
        )
        let tolerance = CMTime(
            seconds: 0.25,
            preferredTimescale: 600
        )

        localPlayer.player.currentItem?.cancelPendingSeeks()
        localPlayer.player.seek(
            to: target,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        )
        play()
        completion(true)
    }

    private func installPlaybackRateMenu() {
        guard #available(iOS 14.0, *) else { return }
        let currentRate = playerLayer?.player.playbackRate ?? 1
        let actions = Self.playbackRates.map { rate in
            let action = UIAction(title: Self.rateTitle(rate)) {
                [weak self] _ in
                self?.playerLayer?.player.playbackRate = rate
                self?.installPlaybackRateMenu()
            }
            action.state = abs(currentRate - rate) < 0.01 ? .on : .off
            return action
        }
        toolBar.playbackRateButton.menu = UIMenu(
            title: "播放速度",
            children: actions
        )
        toolBar.playbackRateButton.showsMenuAsPrimaryAction = true
        toolBar.playbackRateButton.accessibilityLabel = "播放速度"
    }

    private static func rateTitle(_ rate: Float) -> String {
        rate.rounded() == rate
            ? "\(Int(rate))x"
            : "\(rate)x"
    }

    private static func localSeekTime(
        requestedTime: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        let lowerBound = max(requestedTime, 0)
        guard duration.isFinite, duration > 0.1 else {
            return lowerBound
        }
        return min(lowerBound, duration - 0.1)
    }

    private func requestOrientation(_ mask: UIInterfaceOrientationMask) {
        KSOptions.supportedInterfaceOrientations = mask
        let scene = window?.windowScene
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }

        if #available(iOS 16.0, *) {
            enclosingViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
            scene?.requestGeometryUpdate(
                .iOS(interfaceOrientations: mask)
            )
        } else {
            let orientation: UIInterfaceOrientation = mask.contains(.landscapeRight)
                ? .landscapeRight
                : .portrait
            UIDevice.current.setValue(
                orientation.rawValue,
                forKey: "orientation"
            )
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    private var enclosingViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }

    private static let playbackRates: [Float] = [
        0.5,
        0.75,
        1,
        1.25,
        1.5,
        2,
        3,
        4,
        5
    ]
}
