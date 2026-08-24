import SwiftUI

@main
@MainActor
struct PicaVApp: App {
    @UIApplicationDelegateAdaptor(PicaVAppDelegate.self)
    private var appDelegate

    @StateObject private var settings: AppSettings
    @StateObject private var contentContext: AppContentContext
    @StateObject private var remoteImageSettings: RemoteImageSettings
    @StateObject private var client: AnimeAPIClient
    @StateObject private var library: LibraryStore
    @StateObject private var downloads: VideoDownloadService
    @StateObject private var proxyRuntime: AppProxyRuntime

    init() {
        let settings = AppSettings()
        let contentContext = AppContentContext(settings: settings)
        let remoteImageSettings = RemoteImageSettings(settings: settings)
        let proxyRuntime = AppProxyRuntime(settings: settings)
        AnimeImageCacheService.configure()
        AnimeDetailCacheService.configure()
        _settings = StateObject(wrappedValue: settings)
        _contentContext = StateObject(wrappedValue: contentContext)
        _remoteImageSettings = StateObject(
            wrappedValue: remoteImageSettings
        )
        _client = StateObject(wrappedValue: AnimeAPIClient(settings: settings))
        _library = StateObject(
            wrappedValue: LibraryStore(platformID: settings.platformID)
        )
        _downloads = StateObject(
            wrappedValue: VideoDownloadService(
                proxyRuntime: proxyRuntime
            )
        )
        _proxyRuntime = StateObject(
            wrappedValue: proxyRuntime
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(contentContext)
                .environmentObject(remoteImageSettings)
                .environmentObject(client)
                .environmentObject(library)
                .environmentObject(downloads)
                .environmentObject(proxyRuntime)
                .tint(Color(red: 0.43, green: 0.25, blue: 0.92))
        }
    }
}
