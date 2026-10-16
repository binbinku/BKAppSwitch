import Foundation

/// Keep surviving windows in their established positions. Discovery order and
/// focus history may change at every refresh; only new windows are appended.
public struct StableWindowOrder {
    public private(set) var ids: [UUID] = []

    public init() {}

    @discardableResult
    public mutating func reconcile(_ discoveredIDs: [UUID]) -> [UUID] {
        let live = Set(discoveredIDs)
        ids.removeAll { !live.contains($0) }
        var seen = Set(ids)
        for id in discoveredIDs where seen.insert(id).inserted { ids.append(id) }
        return ids
    }
}
