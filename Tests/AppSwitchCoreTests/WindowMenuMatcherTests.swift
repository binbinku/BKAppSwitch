import XCTest
@testable import AppSwitchCore

final class WindowMenuMatcherTests: XCTestCase {
    func testMenuRetainsOffSpaceEntriesWithOnlyOneAXWindow() {
        let menus = ["project-a", "project-b", "project-c", "project-d", "project-e"]
        let matches = WindowMenuMatcher.uniqueMatches(menuTitles: menus, windowTitles: ["project-e"])
        XCTAssertEqual(matches, [4: 0])
        XCTAssertEqual(menus.indices.filter { matches[$0] == nil }.count, 4)
    }

    func testMatchDoesNotDependOnEnumerationOrder() {
        XCTAssertEqual(WindowMenuMatcher.uniqueMatches(menuTitles: ["a", "b", "c"],
                                                       windowTitles: ["c", "a", "b"]), [0: 1, 1: 2, 2: 0])
    }

    func testDuplicateMenuTitlesKeepSeparateMenuTargets() {
        XCTAssertEqual(WindowMenuMatcher.uniqueMatches(menuTitles: ["same", "same", "other"],
                                                       windowTitles: ["same", "other"]), [2: 1])
    }

    func testDuplicateAXTitlesCannotBindToAnArbitraryWindow() {
        XCTAssertEqual(WindowMenuMatcher.uniqueMatches(menuTitles: ["same"],
                                                       windowTitles: ["same", "same"]), [:])
    }

    func testEmptyAndDifferentTitlesDoNotInventAssociations() {
        XCTAssertEqual(WindowMenuMatcher.uniqueMatches(menuTitles: [], windowTitles: ["a"]), [:])
        XCTAssertEqual(WindowMenuMatcher.uniqueMatches(menuTitles: ["a"], windowTitles: []), [:])
        XCTAssertEqual(WindowMenuMatcher.uniqueMatches(menuTitles: ["a"], windowTitles: ["b"]), [:])
    }
}
