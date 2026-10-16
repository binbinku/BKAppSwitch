import Foundation

/// A single frozen list, from key-down through modifier release. Loading and key
/// navigation are modeled here so a quick release cannot discard a pending switch.
public struct SwitchSession {
    public private(set) var isActive = false
    public private(set) var isLoading = false
    public private(set) var ids: [UUID] = []
    public private(set) var selectedIndex = 0
    public private(set) var commitWhenReady = false
    private var initialDirection = 1
    private var pendingSteps = 0

    public init() {}

    public var selectedID: UUID? {
        ids.indices.contains(selectedIndex) ? ids[selectedIndex] : nil
    }

    public mutating func begin(direction: Int) {
        self = SwitchSession()
        isActive = true
        isLoading = true
        initialDirection = direction < 0 ? -1 : 1
    }

    public mutating func move(_ direction: Int) {
        guard isActive else { return }
        if isLoading { pendingSteps += direction; return }
        guard !ids.isEmpty else { return }
        selectedIndex = wrapped(selectedIndex + direction, count: ids.count)
    }

    public mutating func load(ids: [UUID], focusedID: UUID?, preferredID: UUID? = nil) {
        guard isActive, isLoading else { return }
        self.ids = ids
        isLoading = false
        guard !ids.isEmpty else { return }
        if initialDirection > 0, let preferredID, preferredID != focusedID,
           let index = ids.firstIndex(of: preferredID) {
            // Select the recent window without moving any row in the fixed list.
            selectedIndex = wrapped(index + pendingSteps, count: ids.count)
        } else if let focusedID, let index = ids.firstIndex(of: focusedID) {
            selectedIndex = wrapped(index + initialDirection + pendingSteps, count: ids.count)
        } else {
            let first = initialDirection > 0 ? 0 : ids.count - 1
            selectedIndex = wrapped(first + pendingSteps, count: ids.count)
        }
    }

    public mutating func select(_ id: UUID) {
        guard let index = ids.firstIndex(of: id) else { return }
        selectedIndex = index
    }

    public mutating func requestCommit() {
        guard isActive else { return }
        commitWhenReady = true
    }

    public mutating func cancel() { self = SwitchSession() }

    private func wrapped(_ index: Int, count: Int) -> Int { ((index % count) + count) % count }
}
