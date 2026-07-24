import SwiftUI

struct MainTabView: View {
    private enum Selection: Hashable {
        case app(AppTab)
        case search
    }

    @EnvironmentObject private var client: AnimeAPIClient
    @State private var selection: Selection = .app(.home)

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *) {
            searchIntegratedTabView
        } else {
            legacyTabView
        }
    }

    @available(iOS 18.0, *)
    private var searchIntegratedTabView: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(
                    tab.title,
                    systemImage: selection == .app(tab)
                        ? tab.selectedSystemImage
                        : tab.systemImage,
                    value: Selection.app(tab)
                ) {
                    tabNavigationContainer(for: tab)
                }
            }

            Tab(
                "搜索",
                systemImage: "magnifyingglass",
                value: Selection.search,
                role: .search
            ) {
                PicaNavigationContainer {
                    AnimeSearchPage(client: client)
                }
            }
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                tabNavigationContainer(for: tab)
                .tabItem {
                    Label(
                        tab.title,
                        systemImage: selection == .app(tab)
                            ? tab.selectedSystemImage
                            : tab.systemImage
                    )
                }
                .tag(Selection.app(tab))
            }

            PicaNavigationContainer {
                AnimeSearchPage(client: client)
            }
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .tag(Selection.search)
        }
    }

    private func tabNavigationContainer(for tab: AppTab) -> some View {
        PicaNavigationContainer {
            tabContent(for: tab)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomePage(client: client)
        case .explore:
            ExplorePage(client: client)
        case .community:
            CommunityPage(client: client)
        case .profile:
            MyPage(client: client)
        }
    }
}
