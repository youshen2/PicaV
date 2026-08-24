import Combine
import Foundation

@MainActor
final class AppContentContext: ObservableObject {
    struct Snapshot: Equatable {
        let platformID: AnimePlatformID
        let revision: Int

        var identity: String {
            "\(platformID.rawValue)|\(revision)"
        }
    }

    @Published private(set) var snapshot: Snapshot

    var platformID: AnimePlatformID { snapshot.platformID }
    var identity: String { snapshot.identity }

    init(settings: AppSettings) {
        snapshot = Snapshot(
            platformID: settings.platformID,
            revision: settings.contentContextRevision
        )
        settingsSubscription = settings.$platformID
            .combineLatest(settings.$contentContextRevision)
            .map(Snapshot.init(platformID:revision:))
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] snapshot in
                self?.snapshot = snapshot
            }
    }

    private var settingsSubscription: AnyCancellable?
}
