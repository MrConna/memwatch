import XCTest
@testable import MemWatchCore

final class MemoryAnalyzerTests: XCTestCase {
    func testClassifiesCriticalUsedMemory() {
        let analyzer = MemoryAnalyzer()
        let snapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 92,
            availableBytes: 8,
            swapUsedBytes: 0,
            pressure: .normal,
            topProcesses: []
        )

        let analysis = analyzer.analyze(snapshot: snapshot, settings: MemorySettings(notificationsEnabled: false))

        XCTAssertEqual(analysis.level, .critical)
        XCTAssertTrue(analysis.reasons.contains("used memory is 92%"))
    }

    func testSuppressesNotificationUntilSustainedAbnormalSamples() {
        let analyzer = MemoryAnalyzer()
        let settings = MemorySettings(consecutiveSamplesForNotification: 2)
        let snapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 85,
            availableBytes: 20,
            swapUsedBytes: 0,
            pressure: .normal,
            topProcesses: []
        )

        let first = analyzer.analyze(snapshot: snapshot, settings: settings)
        let second = analyzer.analyze(snapshot: snapshot, settings: settings)

        XCTAssertFalse(first.shouldNotify)
        XCTAssertTrue(second.shouldNotify)
        XCTAssertEqual(second.event?.level, .warning)
    }

    func testSwapWarningRaisesWarningLevel() {
        let analyzer = MemoryAnalyzer()
        let snapshot = MemorySnapshot(
            totalBytes: 16 * 1024 * 1024 * 1024,
            usedBytes: 4 * 1024 * 1024 * 1024,
            availableBytes: 8 * 1024 * 1024 * 1024,
            swapUsedBytes: 5 * 1024 * 1024 * 1024,
            pressure: .normal,
            topProcesses: []
        )

        let analysis = analyzer.analyze(snapshot: snapshot, settings: MemorySettings(notificationsEnabled: false))

        XCTAssertEqual(analysis.level, .warning)
        XCTAssertTrue(analysis.reasons.contains("swap is 5.0 GB"))
    }
}
