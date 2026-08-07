import AVFoundation
import KSPlayer
import SwiftUI

struct KSPlayerContainerView: UIViewRepresentable {
    @EnvironmentObject private var proxyRuntime: AppProxyRuntime

    let sources: [PlaybackSource]
    let title: String
    let initialSourceIndex: Int
    let resumeTime: TimeInterval
    let isActive: Bool
    let startsInFullScreen: Bool
    let onProgress: (TimeInterval, TimeInterval) -> Void
    let onPlaybackEnded: () -> Void
    let onSourceChange: (Int) -> Void
    let onFullScreenChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onProgress: onProgress,
            onPlaybackEnded: onPlaybackEnded,
            onSourceChange: onSourceChange,
            onFullScreenChange: onFullScreenChange
        )
    }

    func makeUIView(context: Context) -> PicaPlayerHostView {
        let hostView = PicaPlayerHostView()
        let view = hostView.playerView
        view.backgroundColor = .black
        view.toolBar.definitionButton.accessibilityLabel = "播放线路"
        context.coordinator.attach(to: view, hostView: hostView)
        configure(hostView, coordinator: context.coordinator)
        context.coordinator.updateFullScreenRequest(
            startsInFullScreen
        )
        return hostView
    }

    func updateUIView(_ hostView: PicaPlayerHostView, context: Context) {
        context.coordinator.onProgress = onProgress
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        context.coordinator.onSourceChange = onSourceChange
        context.coordinator.onFullScreenChange = onFullScreenChange
        configure(hostView, coordinator: context.coordinator)
        context.coordinator.updateFullScreenRequest(
            startsInFullScreen
        )
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
        coordinator.detach()
        coordinator.resourceSignature = nil
    }

    private func configure(
        _ hostView: PicaPlayerHostView,
        coordinator: Coordinator
    ) {
        let view = hostView.playerView
        let containsRemoteSource = sources.contains {
            !$0.url.isFileURL
        }
        let requiresProxy =
            containsRemoteSource && proxyRuntime.isProxyRequired
        let mediaProxyURL = proxyRuntime.mediaProxyURL
        if requiresProxy, mediaProxyURL == nil {
            hostView.showStatus(proxyRuntime.mediaStatusText)
            let blockedSignature =
                "proxy-blocked|\(proxyRuntime.mediaStatusText)"
            if coordinator.resourceSignature != blockedSignature {
                view.pause()
                view.resetPlayer()
                coordinator.resourceSignature = blockedSignature
            }
            return
        }
        hostView.showStatus(nil)

        if requiresProxy {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = nil
            KSOptions.useSystemHTTPProxy = false
        } else {
            KSOptions.firstPlayerType = KSAVPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
            KSOptions.useSystemHTTPProxy = true
        }

        let signature = sources
            .map { "\($0.id):\($0.url.absoluteString)" }
            .joined(separator: "|")
            + "|proxy:\(mediaProxyURL?.absoluteString ?? "direct")"
        if coordinator.resourceSignature != signature {
            coordinator.resourceSignature = signature

            let definitions = sources.map { source -> KSPlayerResourceDefinition in
                let options = KSOptions()
                options.startPlayTime = resumeTime
                options.isAccurateSeek = false
                options.isSeekedAutoPlay = true
                options.preferredForwardBufferDuration = 1.5
                if requiresProxy, let mediaProxyURL {
                    options.formatContextOptions["http_proxy"] =
                        mediaProxyURL.absoluteString
                    options.formatContextOptions["rw_timeout"] =
                        20_000_000
                }
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
        var onPlaybackEnded: () -> Void
        var onSourceChange: (Int) -> Void
        var onFullScreenChange: (Bool) -> Void
        var resourceSignature: String?
        var wasActive: Bool?
        private weak var hostView: PicaPlayerHostView?
        private var shouldStartInFullScreen = false
        private var didRequestInitialFullScreen = false

        init(
            onProgress: @escaping (TimeInterval, TimeInterval) -> Void,
            onPlaybackEnded: @escaping () -> Void,
            onSourceChange: @escaping (Int) -> Void,
            onFullScreenChange: @escaping (Bool) -> Void
        ) {
            self.onProgress = onProgress
            self.onPlaybackEnded = onPlaybackEnded
            self.onSourceChange = onSourceChange
            self.onFullScreenChange = onFullScreenChange
        }

        func attach(
            to view: PicaKSPlayerView,
            hostView: PicaPlayerHostView
        ) {
            self.hostView = hostView
            hostView.didAttachToWindow = { [weak self] in
                self?.enterFullScreenIfNeeded()
            }
            view.playTimeDidChange = { [weak self] currentTime, totalTime in
                self?.onProgress(currentTime, totalTime)
            }
            view.playbackDidFinish = { [weak self] in
                self?.onPlaybackEnded()
            }
            view.sourceDidChange = { [weak self] index in
                self?.onSourceChange(index)
            }
            view.fullScreenDidChange = { [weak self] isFullScreen in
                self?.onFullScreenChange(isFullScreen)
            }
            view.backBlock = {}
        }

        func updateFullScreenRequest(_ shouldStart: Bool) {
            shouldStartInFullScreen = shouldStart
            hostView?.playerView.preferredFullScreenOrientationMask =
                shouldStart ? .landscapeRight : nil
            enterFullScreenIfNeeded()
        }

        func detach() {
            hostView?.didAttachToWindow = nil
            hostView = nil
        }

        private func enterFullScreenIfNeeded() {
            guard shouldStartInFullScreen,
                  !didRequestInitialFullScreen,
                  let hostView,
                  hostView.window != nil else {
                return
            }
            didRequestInitialFullScreen = true
            DispatchQueue.main.async { [weak self, weak hostView] in
                guard let self else { return }
                guard self.shouldStartInFullScreen,
                      let hostView,
                      hostView.window != nil else {
                    self.didRequestInitialFullScreen = false
                    return
                }
                hostView.playerView.updateUI(isFullScreen: true)
            }
        }
    }
}

final class PicaPlayerHostView: UIView {
    let playerView = PicaKSPlayerView()
    var didAttachToWindow: (() -> Void)?
    private let statusLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true

        addSubview(playerView)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 24
            ),
            statusLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -24
            )
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            didAttachToWindow?()
        }
    }

    func showStatus(_ message: String?) {
        statusLabel.text = message
        statusLabel.isHidden = message == nil
        if message == nil {
            sendSubviewToBack(statusLabel)
        } else {
            bringSubviewToFront(statusLabel)
        }
    }
}

final class PicaKSPlayerView: IOSVideoPlayerView {
    var playbackDidFinish: (() -> Void)?
    var sourceDidChange: ((Int) -> Void)?
    var fullScreenDidChange: ((Bool) -> Void)?
    var preferredFullScreenOrientationMask: UIInterfaceOrientationMask?

    override func set(
        resource: KSPlayerResource,
        definitionIndex: Int = 0,
        isSetUrl: Bool = true
    ) {
        guard isSetUrl else {
            super.set(
                resource: resource,
                definitionIndex: definitionIndex,
                isSetUrl: false
            )
            return
        }
        loadResource(
            resource,
            definitionIndex: definitionIndex,
            seekTime: nil,
            shouldPlay: true
        )
    }

    override func player(layer: KSPlayerLayer, state: KSPlayerState) {
        super.player(layer: layer, state: state)
        guard layer === playerLayer else { return }
        switch state {
        case .initialized:
            guard playbackPreparationState != .idle else { return }
            playbackPreparationState = .preparing
            applyPlaybackLoadingState()
            schedulePreparationTimeout(for: layer)
            prepareFallbackPlayerOnNextRunLoop(layer)
        case .preparing:
            applyPlaybackLoadingState()
        case .readyToPlay:
            finishPlaybackPreparation(for: layer)
        case .error:
            showPlaybackRetry(message: "视频加载失败，点按重试")
        case .bufferFinished:
            finishPlaybackStartup(for: layer)
        case .paused:
            if playbackPreparationState == .starting,
               !playbackRequested {
                finishPlaybackStartup(for: layer)
            }
        case .buffering:
            if playbackPreparationState == .starting {
                applyPlaybackLoadingState()
            }
        case .playedToTheEnd:
            break
        }
    }

    override func player(
        layer: KSPlayerLayer,
        currentTime: TimeInterval,
        totalTime: TimeInterval
    ) {
        super.player(
            layer: layer,
            currentTime: currentTime,
            totalTime: totalTime
        )
        guard layer === playerLayer,
              playbackPreparationState == .starting,
              currentTime.isFinite,
              currentTime > 0,
              layer.player.playbackState == .playing,
              layer.player.loadState == .playable else {
            return
        }
        finishPlaybackStartup(for: layer)
    }

    override func player(layer: KSPlayerLayer, finish error: Error?) {
        super.player(layer: layer, finish: error)
        if error == nil {
            playbackDidFinish?()
        }
    }

    override func onButtonPressed(
        type: PlayerButtonType,
        button: UIButton
    ) {
        if type == .back,
           fullScreenPresentationState != .inline {
            updateUI(isFullScreen: false)
            return
        }
        if type == .landscape {
            guard fullScreenPresentationState == .inline
                    || fullScreenPresentationState == .fullScreen else {
                return
            }
            updateUI(
                isFullScreen: fullScreenPresentationState == .inline
            )
            return
        }
        if (type == .play || type == .replay),
           playbackPreparationState == .idle || playbackIsStarting {
            applyPlaybackLoadingState()
            return
        }
        super.onButtonPressed(type: type, button: button)
    }

    override func updateUI(isFullScreen: Bool) {
        if isFullScreen {
            guard fullScreenPresentationState == .inline else { return }
            fullScreenPresentationState = .entering
            fullScreenDidChange?(true)
            if !enterFullScreen() {
                fullScreenPresentationState = .inline
                fullScreenDidChange?(false)
            }
        } else {
            switch fullScreenPresentationState {
            case .entering:
                shouldExitAfterPresentation = true
            case .fullScreen:
                fullScreenPresentationState = .exiting
                exitFullScreen()
            case .inline, .exiting:
                return
            }
        }
    }

    override func change(definitionIndex: Int) {
        guard let resource, !resource.definitions.isEmpty else { return }
        let seekTime: TimeInterval?
        if let playerLayer,
           playerLayer.state != .playedToTheEnd,
           playerLayer.player.currentPlaybackTime > 0 {
            seekTime = playerLayer.player.currentPlaybackTime
        } else {
            seekTime = nil
        }
        loadResource(
            resource,
            definitionIndex: definitionIndex,
            seekTime: seekTime,
            shouldPlay: playbackRequested
        )
        sourceDidChange?(definitionIndex)
    }

    override func play() {
        playbackRequested = true
        switch playbackPreparationState {
        case .ready:
            startPreparedPlayback()
        case .failed:
            reloadCurrentResource()
        case .preparing, .starting:
            applyPlaybackLoadingState()
        case .idle:
            if resource != nil {
                reloadCurrentResource()
            }
        }
    }

    override func pause() {
        playbackRequested = false
        guard playbackPreparationState == .ready
                || playbackPreparationState == .starting else {
            toolBar.playButton.isSelected = false
            return
        }
        super.pause()
    }

    override func resetPlayer() {
        preparationTimeoutWorkItem?.cancel()
        super.resetPlayer()
        playbackPreparationState = .idle
        playbackRequested = false
        pendingSeekTime = nil
        applyPlaybackIdleState()
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
        ) { [weak self] finished in
            DispatchQueue.main.async {
                if finished {
                    self?.play()
                }
                completion(finished)
            }
        }
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

    private func loadResource(
        _ resource: KSPlayerResource,
        definitionIndex: Int,
        seekTime: TimeInterval?,
        shouldPlay: Bool
    ) {
        guard !resource.definitions.isEmpty else {
            showPlaybackRetry(message: "没有可用的播放线路")
            return
        }

        preparationTimeoutWorkItem?.cancel()
        if playerLayer != nil {
            super.pause()
        }

        let index = min(
            max(definitionIndex, 0),
            resource.definitions.count - 1
        )
        playbackRequested = shouldPlay
        pendingSeekTime = seekTime
        playbackPreparationState = .preparing
        applyPlaybackLoadingState()

        super.set(
            resource: resource,
            definitionIndex: index,
            isSetUrl: false
        )
        let definition = resource.definitions[index]
        srtControl.url = definition.url
        toolBar.currentTime = 0
        totalTime = 0

        let layer = KSPlayerLayer(
            url: definition.url,
            isAutoPlay: false,
            options: definition.options
        )
        playerLayer = layer
        schedulePreparationTimeout(for: layer)
        layer.prepareToPlay()
    }

    private func finishPlaybackPreparation(for layer: KSPlayerLayer) {
        installPlaybackRateMenu()

        guard let seekTime = pendingSeekTime,
              seekTime > 0,
              layer.player.seekable else {
            pendingSeekTime = nil
            finishPlaybackStartup(for: layer)
            startPreparedPlayback()
            return
        }
        pendingSeekTime = nil
        playbackPreparationState = .starting
        applyPlaybackLoadingState()
        schedulePreparationTimeout(for: layer)
        layer.seek(time: seekTime, autoPlay: false) {
            [weak self, weak layer] _ in
            DispatchQueue.main.async {
                guard let self,
                      let layer,
                      layer === self.playerLayer else {
                    return
                }
                self.finishPlaybackStartup(for: layer)
                self.startPreparedPlayback()
            }
        }
    }

    private func finishPlaybackStartup(for layer: KSPlayerLayer) {
        guard playbackIsStarting else { return }
        preparationTimeoutWorkItem?.cancel()
        playbackPreparationState = .ready
        applyPlaybackReadyState(for: layer)
    }

    private func startPreparedPlayback() {
        guard playbackPreparationState == .ready,
              playbackRequested,
              let layer = playerLayer else {
            return
        }
        playbackPreparationState = .starting
        applyPlaybackLoadingState()
        schedulePreparationTimeout(for: layer)
        super.play()
    }

    private func reloadCurrentResource() {
        guard let resource else {
            showPlaybackRetry(message: "没有可用的视频资源")
            return
        }
        let currentTime = playerLayer?.player.currentPlaybackTime ?? 0
        loadResource(
            resource,
            definitionIndex: currentDefinition,
            seekTime: currentTime > 0 ? currentTime : nil,
            shouldPlay: true
        )
    }

    private func schedulePreparationTimeout(for layer: KSPlayerLayer) {
        preparationTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak layer] in
            guard let self,
                  let layer,
                  layer === self.playerLayer,
                  self.playbackIsStarting else {
                return
            }
            self.showPlaybackRetry(message: "视频加载超时，点按重试")
        }
        preparationTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.preparationTimeout,
            execute: workItem
        )
    }

    private func prepareFallbackPlayerOnNextRunLoop(
        _ layer: KSPlayerLayer
    ) {
        DispatchQueue.main.async { [weak self, weak layer] in
            guard let self,
                  let layer,
                  layer === self.playerLayer,
                  self.playbackPreparationState == .preparing,
                  layer.state == .initialized else {
                return
            }
            layer.prepareToPlay()
        }
    }

    private func showPlaybackRetry(message: String) {
        preparationTimeoutWorkItem?.cancel()
        playbackRequested = false
        playerLayer?.pause()
        playbackPreparationState = .failed
        loadingIndector.isHidden = true
        loadingIndector.stopAnimating()
        toolBar.playButton.isEnabled = true
        toolBar.playButton.isSelected = false
        toolBar.playButton.accessibilityHint = message
        replayButton.isEnabled = true
        replayButton.isHidden = false
        replayButton.isSelected = true
        replayButton.accessibilityLabel = "重新加载视频"
        replayButton.accessibilityHint = message
        toolBar.isSeekable = false
        toolBar.timeSlider.isPlayable = false
    }

    private func applyPlaybackLoadingState() {
        toolBar.playButton.isEnabled = false
        toolBar.playButton.isSelected = false
        replayButton.isEnabled = false
        replayButton.isHidden = true
        replayButton.isSelected = false
        toolBar.isSeekable = false
        toolBar.timeSlider.isPlayable = false
        let loadingHint = "视频加载完成后可播放"
        toolBar.playButton.accessibilityHint = loadingHint
        replayButton.accessibilityHint = loadingHint
        loadingIndector.isHidden = false
        loadingIndector.startAnimating()
    }

    private func applyPlaybackReadyState(for layer: KSPlayerLayer) {
        loadingIndector.isHidden = true
        loadingIndector.stopAnimating()
        toolBar.playButton.isEnabled = true
        toolBar.playButton.isSelected = playbackRequested
        toolBar.playButton.accessibilityHint = nil
        replayButton.isEnabled = true
        replayButton.isHidden = playbackRequested
        replayButton.isSelected = false
        replayButton.accessibilityLabel = "播放视频"
        replayButton.accessibilityHint = nil
        let isSeekable = layer.player.seekable
        toolBar.isSeekable = isSeekable
        toolBar.timeSlider.isPlayable = isSeekable
    }

    private func applyPlaybackIdleState() {
        loadingIndector.isHidden = true
        loadingIndector.stopAnimating()
        toolBar.playButton.isEnabled = false
        toolBar.playButton.isSelected = false
        replayButton.isEnabled = false
        replayButton.isHidden = true
        replayButton.isSelected = false
        toolBar.isSeekable = false
        toolBar.timeSlider.isPlayable = false
    }

    private var playbackIsStarting: Bool {
        switch playbackPreparationState {
        case .preparing, .starting:
            return true
        case .idle, .ready, .failed:
            return false
        }
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

    @discardableResult
    private func enterFullScreen() -> Bool {
        guard fullScreenController == nil,
              let presenter = enclosingViewController,
              let originalSuperview = superview else {
            return false
        }

        originalPlayerSuperview = originalSuperview
        originalPlayerFrame = frame
        originalTranslatesAutoresizingMaskIntoConstraints =
            translatesAutoresizingMaskIntoConstraints
        originalPlayerConstraints = constraintsConnectingPlayer(
            in: originalSuperview
        )
        originalOrientationMask = KSOptions.supportedInterfaceOrientations
        originalPopGestureEnabled = presenter.navigationController?
            .interactivePopGestureRecognizer?.isEnabled
        presenter.navigationController?
            .interactivePopGestureRecognizer?.isEnabled = false

        NSLayoutConstraint.deactivate(originalPlayerConstraints)

        let targetMask: UIInterfaceOrientationMask =
            preferredFullScreenOrientationMask
                ?? (isHorizonal() ? .landscapeRight : .portrait)
        let controller = PicaPlayerFullScreenViewController(
            orientationMask: targetMask
        )
        controller.modalPresentationStyle = .fullScreen
        controller.modalPresentationCapturesStatusBarAppearance = true
        controller.isModalInPresentation = true
        controller.view.backgroundColor = .black

        controller.view.addSubview(self)
        translatesAutoresizingMaskIntoConstraints = false
        fullScreenConstraints = [
            topAnchor.constraint(equalTo: controller.view.topAnchor),
            leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
        ]
        NSLayoutConstraint.activate(fullScreenConstraints)

        fullScreenPresenter = presenter
        fullScreenController = controller
        landscapeButton.isSelected = true
        KSOptions.supportedInterfaceOrientations = targetMask
        super.updateUI(isLandscape: targetMask != .portrait)

        presenter.present(controller, animated: true) { [weak self] in
            guard let self else { return }
            fullScreenPresentationState = .fullScreen
            requestOrientation(targetMask)
            refreshPlayerLayout()
            if shouldExitAfterPresentation {
                shouldExitAfterPresentation = false
                updateUI(isFullScreen: false)
            }
        }
        return true
    }

    private func exitFullScreen() {
        guard let controller = fullScreenController else { return }
        let restoreMask = originalOrientationMask ?? .portrait
        controller.orientationMask = restoreMask
        KSOptions.supportedInterfaceOrientations = restoreMask
        requestOrientation(restoreMask)

        let presenter =
            controller.presentingViewController ?? fullScreenPresenter
        presenter?.dismiss(animated: true) { [weak self] in
            self?.restoreInlinePlayer(orientationMask: restoreMask)
        }
    }

    private func restoreInlinePlayer(
        orientationMask: UIInterfaceOrientationMask
    ) {
        NSLayoutConstraint.deactivate(fullScreenConstraints)
        fullScreenConstraints = []

        if let originalPlayerSuperview {
            originalPlayerSuperview.addSubview(self)
            translatesAutoresizingMaskIntoConstraints =
                originalTranslatesAutoresizingMaskIntoConstraints
            frame = originalPlayerFrame
            NSLayoutConstraint.activate(originalPlayerConstraints)
        }

        fullScreenPresenter?.navigationController?
            .interactivePopGestureRecognizer?.isEnabled =
                originalPopGestureEnabled ?? true
        originalPlayerConstraints = []
        fullScreenController = nil
        fullScreenPresenter = nil
        originalPlayerSuperview = nil
        fullScreenPresentationState = .inline
        shouldExitAfterPresentation = false
        landscapeButton.isSelected = false
        super.updateUI(isLandscape: false)
        fullScreenDidChange?(false)
        requestOrientation(orientationMask)
        refreshPlayerLayout()
        if playerLayer?.state.isPlaying == true {
            play()
        }
    }

    private func constraintsConnectingPlayer(
        in superview: UIView
    ) -> [NSLayoutConstraint] {
        var result = superview.constraints.filter {
            $0.firstItem === self || $0.secondItem === self
        }
        result.append(
            contentsOf: constraints.filter {
                $0.firstItem === self
                    && ($0.firstAttribute == .width
                        || $0.firstAttribute == .height)
            }
        )
        var seen = Set<ObjectIdentifier>()
        return result.filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    private func refreshPlayerLayout() {
        superview?.setNeedsLayout()
        superview?.layoutIfNeeded()
        setNeedsLayout()
        layoutIfNeeded()
        playerLayer?.player.view?.setNeedsLayout()
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
    private static let preparationTimeout: TimeInterval = 20
    private weak var originalPlayerSuperview: UIView?
    private weak var fullScreenPresenter: UIViewController?
    private weak var fullScreenController: PicaPlayerFullScreenViewController?
    private var originalPlayerFrame = CGRect.zero
    private var originalPlayerConstraints: [NSLayoutConstraint] = []
    private var fullScreenConstraints: [NSLayoutConstraint] = []
    private var originalOrientationMask: UIInterfaceOrientationMask?
    private var originalPopGestureEnabled: Bool?
    private var originalTranslatesAutoresizingMaskIntoConstraints = false
    private var fullScreenPresentationState: FullScreenPresentationState =
        .inline
    private var shouldExitAfterPresentation = false
    private var playbackPreparationState: PlaybackPreparationState = .idle
    private var playbackRequested = true
    private var pendingSeekTime: TimeInterval?
    private var preparationTimeoutWorkItem: DispatchWorkItem?

    private enum PlaybackPreparationState {
        case idle
        case preparing
        case starting
        case ready
        case failed
    }

    private enum FullScreenPresentationState {
        case inline
        case entering
        case fullScreen
        case exiting
    }
}
