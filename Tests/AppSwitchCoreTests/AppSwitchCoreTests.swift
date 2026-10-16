import XCTest
@testable import AppSwitchCore

final class WindowTitleTests: XCTestCase {
    func testDefaultMacTitlePreservesHyphensAndRemote() {
        let title = WindowTitle("main.go — backend-api [SSH: dev-server]")
        XCTAssertEqual(title.project, "backend-api [SSH: dev-server]")
        XCTAssertEqual(title.original, "main.go — backend-api [SSH: dev-server]")
    }

    func testProjectFirstAndWindowsStyleSuffix() {
        XCTAssertEqual(WindowTitle("AppSwitch — App.swift").project, "AppSwitch")
        XCTAssertEqual(WindowTitle("main.go - backend-api - Visual Studio Code").project, "backend-api")
        XCTAssertEqual(WindowTitle("main.go - backend-api - Code - Insiders").project, "backend-api")
        XCTAssertEqual(WindowTitle("backend-api - Visual Studio Code - Insiders").project, "backend-api")
        XCTAssertEqual(WindowTitle("backend-api — Code - Insiders").project, "backend-api")
    }

    func testModesResolveAmbiguousCustomTitles() {
        XCTAssertEqual(WindowTitle("foo — bar", mode: .projectFirst).project, "foo")
        XCTAssertEqual(WindowTitle("foo — bar", mode: .editorFirst).project, "bar")
        XCTAssertEqual(WindowTitle("foo — bar", mode: .original).project, "foo — bar")
        XCTAssertEqual(WindowTitle("App.swift — AppSwitch — Work", mode: .editorFirst).project, "AppSwitch")
    }

    func testEmptyAndSingleComponentTitles() {
        XCTAssertEqual(WindowTitle("  ").project, "未命名窗口")
        XCTAssertEqual(WindowTitle("backend-api").project, "backend-api")
        XCTAssertEqual(WindowTitle("  foo.code-workspace  ").project, "foo.code-workspace")
        XCTAssertEqual(WindowTitle("AppSwitch — .gitignore").project, "AppSwitch")
    }
}

final class SwitchSessionTests: XCTestCase {
    func testFirstTabSelectsPreviousWindowAndWrapsBothDirections() {
        let ids = [UUID(), UUID(), UUID()]
        var session = SwitchSession()
        session.begin(direction: 1)
        session.load(ids: ids, focusedID: ids[0])
        XCTAssertEqual(session.selectedID, ids[1])
        session.move(1)
        XCTAssertEqual(session.selectedID, ids[2])
        session.move(1)
        XCTAssertEqual(session.selectedID, ids[0])
        session.move(-1)
        XCTAssertEqual(session.selectedID, ids[2])
    }

    func testInvocationOutsideCodeSelectsMostRecentFirst() {
        let ids = [UUID(), UUID(), UUID()]
        var session = SwitchSession()
        session.begin(direction: 1)
        session.load(ids: ids, focusedID: nil)
        XCTAssertEqual(session.selectedID, ids[0])
        session.begin(direction: -1)
        session.load(ids: ids, focusedID: nil)
        XCTAssertEqual(session.selectedID, ids[2])
    }

    func testFastRepeatedTabsAndReleaseDuringLoadingAreRetained() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        var session = SwitchSession()
        session.begin(direction: 1)
        session.move(1)
        session.move(1)
        session.requestCommit()
        XCTAssertTrue(session.isLoading)
        session.load(ids: ids, focusedID: ids[0])
        XCTAssertEqual(session.selectedID, ids[3])
        XCTAssertTrue(session.commitWhenReady)
    }

    func testCancellationRejectsLateLoadingResult() {
        var session = SwitchSession()
        session.begin(direction: 1)
        session.requestCommit()
        session.cancel()
        session.load(ids: [UUID()], focusedID: nil)
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.selectedID)
        XCTAssertFalse(session.commitWhenReady)
    }

    func testEmptyAndOneWindowSessions() {
        var session = SwitchSession()
        session.begin(direction: -1)
        session.load(ids: [], focusedID: nil)
        session.move(-1)
        XCTAssertNil(session.selectedID)
        let id = UUID()
        session.begin(direction: -1)
        session.load(ids: [id], focusedID: id)
        session.move(1)
        XCTAssertEqual(session.selectedID, id)
    }

    func testDuplicateTitlesDoNotAffectIdentityAndSnapshotDoesNotReorder() {
        let ids = [UUID(), UUID()]
        var session = SwitchSession()
        session.begin(direction: 1)
        session.load(ids: ids, focusedID: ids[0])
        session.load(ids: ids.reversed(), focusedID: ids[1])
        XCTAssertEqual(session.ids, ids)
        XCTAssertEqual(session.selectedID, ids[1])
        session.select(ids[0])
        XCTAssertEqual(session.selectedID, ids[0])
    }
}
