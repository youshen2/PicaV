import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: VideoDownloadService

    var body: some View {
        MainTabView()
            .id(settings.contentContextIdentity)
            .onAppear {
                library.selectPlatform(settings.platformID)
                downloads.setProxyProtectionEnabled(
                    settings.appProxyEnabled
                )
            }
            .onChange(of: settings.platformID) { platformID in
                library.selectPlatform(platformID)
            }
            .onChange(of: settings.appProxyEnabled) { isEnabled in
                downloads.setProxyProtectionEnabled(isEnabled)
            }
    }
}
