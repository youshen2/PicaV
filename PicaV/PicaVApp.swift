import SwiftUI

@main
@MainActor
struct PicaVApp: App {
    @UIApplicationDelegateAdaptor(PicaVAppDelegate.self)
    private var appDelegate

    @StateObject private var settings: AppSettings
    @StateObject private var client: AnimeAPIClient
    @StateObject private var library: LibraryStore
    @StateObject private var downloads: VideoDownloadService

    init() {
        let settings = AppSettings()
        AnimeImageCacheService.configure()
        AnimeDetailCacheService.configure()
        _settings = StateObject(wrappedValue: settings)
        _client = StateObject(wrappedValue: AnimeAPIClient(settings: settings))
        _library = StateObject(
            wrappedValue: LibraryStore(platformID: settings.platformID)
        )
        _downloads = StateObject(wrappedValue: VideoDownloadService())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(client)
                .environmentObject(library)
                .environmentObject(downloads)
                .tint(Color(red: 0.43, green: 0.25, blue: 0.92))
        }
    }
}
