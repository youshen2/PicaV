import Combine
import Foundation

@MainActor
final class RemoteImageSettings: ObservableObject {
    @Published private(set) var revision = 0

    var platformID: AnimePlatformID { settings.platformID }
    var apiBaseURL: URL { settings.apiBaseURL }
    var useImageProxy: Bool { settings.useImageProxy }
    var routeRevision: Int { settings.appProxyRevision }
    var imageConfiguration: PlatformImageConfiguration {
        settings.activePlatform.imageConfiguration
    }

    init(settings: AppSettings) {
        self.settings = settings
        settingsSubscription = Publishers.CombineLatest4(
            settings.$platformID,
            settings.$baseURLText,
            settings.$apiPrefix,
            settings.$useImageProxy
        )
        .combineLatest(settings.$appProxyRevision)
        .dropFirst()
        .sink { [weak self] _ in
            self?.revision &+= 1
        }
    }

    func networkRoute() throws -> AppNetworkRoute {
        try settings.appNetworkRoute()
    }

    private let settings: AppSettings
    private var settingsSubscription: AnyCancellable?
}
