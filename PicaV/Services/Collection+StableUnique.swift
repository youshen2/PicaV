import Foundation

extension Array {
    func stableUniqued<ID: Hashable>(
        seededBy existingIDs: Set<ID> = [],
        id: (Element) -> ID
    ) -> [Element] {
        var knownIDs = existingIDs
        return filter { knownIDs.insert(id($0)).inserted }
    }
}
