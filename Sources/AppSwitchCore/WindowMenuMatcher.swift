import Foundation

public enum WindowMenuMatcher {
    /// Resolve strong object matches before using unique-title fallbacks. Reserve
    /// every strong identity up front, so a renamed window cannot donate its ID
    /// to another menu row that happens to have its old title.
    public static func stableIDs(menuTitles: [String], previousTitles: [String], previousIDs: [UUID],
                                 strongMatches: [Int: UUID]) -> [Int: UUID] {
        guard previousTitles.count == previousIDs.count else { return strongMatches }
        let reserved = Set(strongMatches.values)
        var used = Set<UUID>()
        var resolved: [Int: UUID] = [:]
        for index in menuTitles.indices {
            if let id = strongMatches[index], used.insert(id).inserted { resolved[index] = id }
        }
        let titles = uniqueMatches(menuTitles: menuTitles, windowTitles: previousTitles)
        for index in menuTitles.indices where resolved[index] == nil {
            guard let previousIndex = titles[index] else { continue }
            let id = previousIDs[previousIndex]
            guard !reserved.contains(id), used.insert(id).inserted else { continue }
            resolved[index] = id
        }
        return resolved
    }

    /// Attach an AX window to a menu entry only when the title identifies exactly
    /// one candidate on both sides. Duplicate titles must keep their exact menu
    /// targets instead of being collapsed or bound to an arbitrary AX window.
    public static func uniqueMatches(menuTitles: [String], windowTitles: [String]) -> [Int: Int] {
        let menus = Dictionary(grouping: menuTitles.indices, by: { menuTitles[$0] })
        let windows = Dictionary(grouping: windowTitles.indices, by: { windowTitles[$0] })
        var matches: [Int: Int] = [:]
        for (title, indices) in menus where indices.count == 1 {
            guard let candidates = windows[title], candidates.count == 1 else { continue }
            matches[indices[0]] = candidates[0]
        }
        return matches
    }
}
