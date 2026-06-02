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

    func testPresetThresholds() {
        XCTAssertEqual(MemorySensitivityPreset.balanced.settings.warningUsedRatio, 0.80)
        XCTAssertEqual(MemorySensitivityPreset.sensitive.settings.warningUsedRatio, 0.70)
        XCTAssertEqual(MemorySensitivityPreset.relaxed.settings.warningUsedRatio, 0.88)
    }

    func testEventMessageIncludesMetricsAndTopProcess() {
        let analyzer = MemoryAnalyzer()
        let snapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 92,
            availableBytes: 4,
            swapUsedBytes: 5 * 1024 * 1024 * 1024,
            pressure: .critical,
            topProcesses: [
                ProcessUsage(pid: 1, name: "Google Chrome Helper (Renderer)", residentBytes: 3 * 1024 * 1024 * 1024, kind: .renderer)
            ]
        )

        _ = analyzer.analyze(snapshot: snapshot, settings: MemorySettings(consecutiveSamplesForNotification: 2))
        let analysis = analyzer.analyze(snapshot: snapshot, settings: MemorySettings(consecutiveSamplesForNotification: 2))

        XCTAssertTrue(analysis.event?.message.contains("92%") ?? false)
        XCTAssertTrue(analysis.event?.message.contains("5.0 GB swap") ?? false)
        XCTAssertTrue(analysis.event?.message.contains("Google Chrome Helper") ?? false)
    }

    func testDetectsFastGrowingProcessAcrossSamples() {
        let analyzer = MemoryAnalyzer()
        let settings = MemorySettings(notificationsEnabled: false)
        let first = MemorySnapshot(
            totalBytes: 16 * 1024 * 1024 * 1024,
            usedBytes: 8 * 1024 * 1024 * 1024,
            availableBytes: 4 * 1024 * 1024 * 1024,
            swapUsedBytes: 0,
            pressure: .normal,
            topProcesses: [
                ProcessUsage(pid: 42, name: "Google Chrome Helper (Renderer)", residentBytes: 400 * 1024 * 1024, kind: .renderer, appName: "Google Chrome")
            ]
        )
        let second = MemorySnapshot(
            totalBytes: 16 * 1024 * 1024 * 1024,
            usedBytes: 9 * 1024 * 1024 * 1024,
            availableBytes: 3 * 1024 * 1024 * 1024,
            swapUsedBytes: 0,
            pressure: .normal,
            topProcesses: [
                ProcessUsage(pid: 42, name: "Google Chrome Helper (Renderer)", residentBytes: 950 * 1024 * 1024, kind: .renderer, appName: "Google Chrome")
            ]
        )

        _ = analyzer.analyze(snapshot: first, settings: settings)
        let analysis = analyzer.analyze(snapshot: second, settings: settings)

        XCTAssertEqual(analysis.growingProcess?.pid, 42)
        XCTAssertTrue(analysis.reasons.contains { $0.contains("grew by 550 MB") })
    }
}
