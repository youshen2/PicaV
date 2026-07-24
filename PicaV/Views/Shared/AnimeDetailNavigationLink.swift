import SwiftUI

struct AnimeDetailTransitionID: Hashable {
    private let platformID: AnimePlatformID
    private let animeID: String

    init(anime: Anime, platformID: AnimePlatformID) {
        self.platformID = platformID
        animeID = anime.id
    }
}

struct AnimeDetailNavigationLink<Label: View>: View {
    private let anime: Anime
    private let client: AnimeAPIClient
    private let onNavigate: () -> Void
    private let label: () -> Label

    @Namespace private var transitionNamespace

    init(
        anime: Anime,
        client: AnimeAPIClient,
        onNavigate: @escaping () -> Void = {},
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.anime = anime
        self.client = client
        self.onNavigate = onNavigate
        self.label = label
    }

    var body: some View {
        NavigationLink {
            AnimeDetailPage(
                videoID: anime.id,
                preview: anime,
                client: client
            )
            .picaVAnimeDetailZoomDestination(
                sourceID: transitionID,
                in: transitionNamespace
            )
        } label: {
            label()
                .picaVAnimeDetailTransitionSource(
                    id: transitionID,
                    in: transitionNamespace
                )
        }
        .simultaneousGesture(
            TapGesture().onEnded(onNavigate)
        )
    }

    private var transitionID: AnimeDetailTransitionID {
        AnimeDetailTransitionID(
            anime: anime,
            platformID: client.platformID
        )
    }
}

extension AnimeDetailNavigationLink {
    func onNavigate(_ action: @escaping () -> Void) -> AnimeDetailNavigationLink {
        AnimeDetailNavigationLink(
            anime: anime,
            client: client,
            onNavigate: action,
            label: label
        )
    }
}

extension View {
    func picaVAnimeDetailTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> some View {
        modifier(
            AnimeDetailTransitionSourceModifier(
                id: id,
                namespace: namespace
            )
        )
    }

    fileprivate func picaVAnimeDetailZoomDestination<ID: Hashable>(
        sourceID: ID,
        in namespace: Namespace.ID
    ) -> some View {
        modifier(
            AnimeDetailZoomDestinationModifier(
                sourceID: sourceID,
                namespace: namespace
            )
        )
    }
}

private struct AnimeDetailTransitionSourceModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct AnimeDetailZoomDestinationModifier<ID: Hashable>: ViewModifier {
    let sourceID: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(
                .zoom(sourceID: sourceID, in: namespace)
            )
        } else {
            content
        }
    }
}
