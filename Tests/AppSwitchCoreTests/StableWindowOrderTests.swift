import XCTest
@testable import AppSwitchCore

final class StableWindowOrderTests: XCTestCase {
    func testFocusAndDiscoveryReorderingDoNotMoveRows() {
        let ids = (0..<4).map { _ in UUID() }
        var order = StableWindowOrder()
        XCTAssertEqual(order.reconcile(ids), ids)
        XCTAssertEqual(order.reconcile([ids[2], ids[0], ids[3], ids[1]]), ids)
        XCTAssertEqual(order.reconcile(ids.reversed()), ids)
    }

    func testNewWindowIsAppendedEvenIfOSReturnsItFirst() {
        let a = UUID(), b = UUID(), new = UUID()
        var order = StableWindowOrder()
        order.reconcile([a, b])
        XCTAssertEqual(order.reconcile([new, b, a]), [a, b, new])
    }

    func testClosingWindowPreservesSurvivorsRelativeOrder() {
        let a = UUID(), b = UUID(), c = UUID(), new = UUID()
        var order = StableWindowOrder()
        order.reconcile([a, b, c])
        XCTAssertEqual(order.reconcile([c, a, new]), [a, c, new])
        XCTAssertEqual(order.reconcile([new, c, a, b]), [a, c, new, b])
    }

    func testRecreatedReorderedMenusRecoverExistingWindowPositions() {
        let ids = [UUID(), UUID(), UUID()]
        let oldTitles = ["A — project-a", "B — project-b", "C — project-c"]
        let newTitles = [oldTitles[2], oldTitles[0], oldTitles[1]]
        let matches = WindowMenuMatcher.stableIDs(menuTitles: newTitles, previousTitles: oldTitles,
                                                 previousIDs: ids, strongMatches: [:])
        let recoveredIDs = newTitles.indices.map { matches[$0]! }
        var order = StableWindowOrder()
        order.reconcile(ids)
        XCTAssertEqual(order.reconcile(recoveredIDs), ids)
    }

    func testEmptyListsAndDuplicateDiscoveryDoNotLeaveStaleRows() {
        let a = UUID(), b = UUID()
        var order = StableWindowOrder()
        XCTAssertEqual(order.reconcile([a, a, b]), [a, b])
        XCTAssertEqual(order.reconcile([]), [])
        XCTAssertEqual(order.reconcile([b, a]), [b, a])
    }

    func testRetitledWindowDoesNotDonateItsIdentityToAnotherMenuRow() {
        let a = UUID(), b = UUID()
        let matches = WindowMenuMatcher.stableIDs(menuTitles: ["bar", "foo"], previousTitles: ["foo", "bar"],
                                                 previousIDs: [a, b], strongMatches: [0: a])
        XCTAssertEqual(matches[0], a)
        XCTAssertNil(matches[1])
    }

    func testDuplicateTitlesKeepStrongIdentitiesButDoNotGuessWeakOnes() {
        let a = UUID(), b = UUID(), c = UUID()
        let matches = WindowMenuMatcher.stableIDs(menuTitles: ["same", "same", "other"],
            previousTitles: ["same", "same", "other"], previousIDs: [a, b, c], strongMatches: [0: b, 1: a])
        XCTAssertEqual(matches, [0: b, 1: a, 2: c])
        let ambiguous = WindowMenuMatcher.stableIDs(menuTitles: ["same", "same"], previousTitles: ["same", "same"],
                                                   previousIDs: [a, b], strongMatches: [:])
        XCTAssertTrue(ambiguous.isEmpty)
    }

    func testTitleFallbackCannotStealAnObjectMatchThatAppearsLater() {
        let a = UUID(), b = UUID()
        let matches = WindowMenuMatcher.stableIDs(menuTitles: ["foo", "changed"], previousTitles: ["foo", "bar"],
                                                 previousIDs: [a, b], strongMatches: [1: a])
        XCTAssertNil(matches[0])
        XCTAssertEqual(matches[1], a)
    }

    func testRecentWindowHighlightDoesNotReorderAndFurtherTabsFollowFixedOrder() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        var session = SwitchSession()
        session.begin(direction: 1)
        session.load(ids: ids, focusedID: ids[0], preferredID: ids[2])
        XCTAssertEqual(session.selectedID, ids[2])
        XCTAssertEqual(session.ids, ids)
        session.move(1)
        XCTAssertEqual(session.selectedID, ids[3])
        session.move(-1)
        XCTAssertEqual(session.selectedID, ids[2])
        XCTAssertEqual(session.ids, ids)
    }

    func testFastRepeatedKeysDuringLoadingApplyAfterRecentHighlight() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        var session = SwitchSession()
        session.begin(direction: 1)
        session.move(1)
        session.requestCommit()
        session.load(ids: ids, focusedID: ids[0], preferredID: ids[2])
        XCTAssertEqual(session.selectedID, ids[3])
        XCTAssertTrue(session.commitWhenReady)
    }

    func testBackwardNavigationAndStalePreferredIDUseFixedOrder() {
        let ids = [UUID(), UUID(), UUID()]
        var session = SwitchSession()
        session.begin(direction: -1)
        session.load(ids: ids, focusedID: ids[0], preferredID: ids[1])
        XCTAssertEqual(session.selectedID, ids[2])
        session.begin(direction: 1)
        session.load(ids: ids, focusedID: ids[0], preferredID: UUID())
        XCTAssertEqual(session.selectedID, ids[1])
    }

    func testInvocationOutsideTrackedAppsSelectsRecentWithoutMovingIt() {
        let ids = [UUID(), UUID(), UUID()]
        var session = SwitchSession()
        session.begin(direction: 1)
        session.load(ids: ids, focusedID: nil, preferredID: ids[2])
        XCTAssertEqual(session.selectedID, ids[2])
        XCTAssertEqual(session.ids, ids)
    }
}
