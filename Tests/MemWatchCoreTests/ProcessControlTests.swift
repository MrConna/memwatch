import XCTest
@testable import MemWatchCore

final class ProcessControlTests: XCTestCase {
    func testRendererProcessOffersSafeAndDestructiveControls() {
        let process = ProcessUsage(
            pid: 42,
            name: "Google Chrome Helper (Renderer)",
            residentBytes: 2 * 1024 * 1024 * 1024,
            kind: .renderer,
            appName: "Google Chrome"
        )

        let actions = ProcessControl.actions(for: process)

        XCTAssertEqual(actions.map(\.kind), [.activateApp, .quitApp, .forceQuitProcess])
        XCTAssertFalse(actions[0].requiresConfirmation)
        XCTAssertTrue(actions[1].requiresConfirmation)
        XCTAssertTrue(actions[2].requiresConfirmation)
        XCTAssertEqual(actions[1].title, "Quit Google Chrome")
        XCTAssertTrue(actions[2].detail.contains("PID 42"))
    }

    func testMainAppProcessMakesQuitRiskExplicit() {
        let process = ProcessUsage(
            pid: 100,
            name: "Lark",
            residentBytes: 3 * 1024 * 1024 * 1024,
            kind: .mainApp,
            appName: "Lark"
        )

        let quitAction = ProcessControl.actions(for: process).first { $0.kind == .quitApp }

        XCTAssertEqual(quitAction?.title, "Quit Lark")
        XCTAssertTrue(quitAction?.detail.contains("all related windows") ?? false)
        XCTAssertTrue(quitAction?.requiresConfirmation ?? false)
    }
}
