import XCTest
@testable import MemWatchCore

final class MenuStatusTests: XCTestCase {
    func testMenuStatusPrioritizesCriticalPressure() {
        let snapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 91,
            availableBytes: 9,
            swapUsedBytes: 0,
            pressure: .critical,
            topProcesses: []
        )
        let analysis = MemoryAnalysis(level: .critical, reasons: [], shouldNotify: false, event: nil)

        XCTAssertEqual(MenuStatus.title(snapshot: snapshot, analysis: analysis), "MEM !!")
    }

    func testMenuStatusShowsSwapBeforeMemoryPercent() {
        let snapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 50,
            availableBytes: 50,
            swapUsedBytes: 6 * 1024 * 1024 * 1024,
            pressure: .warning,
            topProcesses: []
        )
        let analysis = MemoryAnalysis(level: .warning, reasons: [], shouldNotify: false, event: nil)

        XCTAssertEqual(MenuStatus.title(snapshot: snapshot, analysis: analysis), "SWAP 6G")
    }

    func testMenuStatusShowsGrowthBeforeNormalMemoryPercent() {
        let snapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 50,
            availableBytes: 50,
            swapUsedBytes: 0,
            pressure: .normal,
            topProcesses: []
        )
        let growth = ProcessGrowth(pid: 1, name: "Chrome", appName: "Chrome", previousBytes: 0, currentBytes: 700 * 1024 * 1024)
        let analysis = MemoryAnalysis(level: .normal, reasons: [], shouldNotify: false, event: nil, growingProcess: growth)

        XCTAssertEqual(MenuStatus.title(snapshot: snapshot, analysis: analysis), "MEM UP")
    }

    func testMenuStatusFallsBackToMemoryPercent() {
        let snapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 54,
            availableBytes: 46,
            swapUsedBytes: 0,
            pressure: .normal,
            topProcesses: []
        )
        let analysis = MemoryAnalysis(level: .normal, reasons: [], shouldNotify: false, event: nil)

        XCTAssertEqual(MenuStatus.title(snapshot: snapshot, analysis: analysis), "MEM 54%")
    }
}
