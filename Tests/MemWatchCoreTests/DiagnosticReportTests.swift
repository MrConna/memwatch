import XCTest
@testable import MemWatchCore

final class DiagnosticReportTests: XCTestCase {
    func testReportIncludesSummaryReasonsAppsProcessesAndRecommendations() {
        let snapshot = MemorySnapshot(
            sampledAt: Date(timeIntervalSince1970: 1_717_200_000),
            totalBytes: 16 * 1024 * 1024 * 1024,
            usedBytes: 14 * 1024 * 1024 * 1024,
            availableBytes: 900 * 1024 * 1024,
            swapUsedBytes: 5 * 1024 * 1024 * 1024,
            pressure: .warning,
            topProcesses: [
                ProcessUsage(pid: 42, name: "Google Chrome Helper (Renderer)", residentBytes: 3 * 1024 * 1024 * 1024, kind: .renderer, appName: "Google Chrome"),
                ProcessUsage(pid: 43, name: "Google Chrome", residentBytes: 800 * 1024 * 1024, kind: .mainApp, appName: "Google Chrome"),
                ProcessUsage(pid: 50, name: "Lark Helper (Renderer)", residentBytes: 700 * 1024 * 1024, kind: .renderer, appName: "Lark")
            ]
        )
        let analysis = MemoryAnalysis(
            level: .warning,
            reasons: ["swap is 5.0 GB", "available memory is 900 MB"],
            shouldNotify: false,
            event: nil
        )

        let report = DiagnosticReport.text(snapshot: snapshot, analysis: analysis)

        XCTAssertTrue(report.contains("MemWatch Diagnostic Report"))
        XCTAssertTrue(report.contains("State: warning"))
        XCTAssertTrue(report.contains("Used: 14.0 GB / 16.0 GB (88%)"))
        XCTAssertTrue(report.contains("Swap: 5.0 GB"))
        XCTAssertTrue(report.contains("- swap is 5.0 GB"))
        XCTAssertTrue(report.contains("Google Chrome: 3.8 GB across 2 process(es)"))
        XCTAssertTrue(report.contains("Google Chrome Helper (Renderer) [42] Renderer: 3.0 GB"))
        XCTAssertTrue(report.contains("Use Chrome Task Manager or close the related tab"))
    }
}
