import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        MainTabView()
            .id(settings.contentContextIdentity)
            .onAppear {
                library.selectPlatform(settings.platformID)
            }
            .onChange(of: settings.platformID) { platformID in
                library.selectPlatform(platformID)
            }
    }
}
