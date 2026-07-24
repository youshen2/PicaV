import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        MainTabView()
            .id(settings.platformID)
    }
}
