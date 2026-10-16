import XCTest
@testable import AppSwitchCore

final class ApplicationSelectionTests: XCTestCase {
    private let code = TrackedApplication(bundleIdentifier: "com.microsoft.VSCode", name: "Code", path: "/Applications/Code.app")
    private let browser = TrackedApplication(bundleIdentifier: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app")

    func testAddingApplicationsIncludesOnlyExplicitChoices() {
        var selection = ApplicationSelection([code])
        selection.add(browser)
        XCTAssertEqual(selection.enabledBundleIDs, [code.id, browser.id])
        XCTAssertFalse(selection.enabledBundleIDs.contains("com.apple.Terminal"))
    }

    func testReAddingUpdatesMovedApplicationAndEnablesItWithoutDuplicates() {
        var selection = ApplicationSelection([code, browser])
        selection.setEnabled(false, for: browser.id)
        var moved = browser
        moved.path = "/Users/example/Applications/Safari.app"
        selection.add(moved)
        XCTAssertEqual(selection.applications.count, 2)
        XCTAssertEqual(selection.applications[1].path, moved.path)
        XCTAssertTrue(selection.enabledBundleIDs.contains(browser.id))
    }

    func testDisabledApplicationsRemainSavedAcrossRestarts() throws {
        var selection = ApplicationSelection([code, browser])
        selection.setEnabled(false, for: code.id)
        let restored = try JSONDecoder().decode(ApplicationSelection.self, from: JSONEncoder().encode(selection))
        XCTAssertEqual(restored, selection)
        XCTAssertEqual(restored.enabledBundleIDs, [browser.id])
    }

    func testRemovingEveryApplicationPersistsAnEmptySelection() throws {
        var selection = ApplicationSelection([code])
        selection.remove(code.id)
        let restored = try JSONDecoder().decode(ApplicationSelection.self, from: JSONEncoder().encode(selection))
        XCTAssertTrue(restored.applications.isEmpty)
        XCTAssertTrue(restored.enabledBundleIDs.isEmpty)
    }

    func testInitializationRejectsEmptyIdentifiersAndDuplicates() {
        let invalid = TrackedApplication(bundleIdentifier: " ", name: "Invalid", path: "/tmp/Invalid.app")
        let selection = ApplicationSelection([code, code, invalid, browser])
        XCTAssertEqual(selection.applications.map(\.id), [code.id, browser.id])
    }
}
