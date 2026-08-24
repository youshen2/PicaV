import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var contentContext: AppContentContext
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        MainTabView()
            .id(contentContext.identity)
            .onAppear {
                library.selectPlatform(contentContext.platformID)
            }
            .onChange(of: contentContext.platformID) { platformID in
                library.selectPlatform(platformID)
            }
    }
}
