import XCTest
@testable import MemWatchCore

final class MemorySamplerTests: XCTestCase {
    func testParsesTotalMemoryFromSysctl() throws {
        let bytes = try MemorySampler.parseTotalMemory("hw.memsize: 17179869184\n")

        XCTAssertEqual(bytes, 17_179_869_184)
    }

    func testParsesVmStatPagesIntoMemoryCounters() throws {
        let output = """
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                               1024.
        Pages active:                             2000.
        Pages inactive:                           3000.
        Pages speculative:                        512.
        Pages wired down:                         4000.
        Pages compressed:                         1000.
        """

        let counters = try MemorySampler.parseVMStat(output, totalMemoryBytes: 16_384 * 20_000)

        XCTAssertEqual(counters.pageSize, 16_384)
        XCTAssertEqual(counters.freeBytes, 16_384 * (1024 + 512))
        XCTAssertEqual(counters.usedBytes, 16_384 * (2000 + 3000 + 4000 + 1000))
        XCTAssertEqual(counters.availableBytes, 16_384 * (1024 + 512 + 3000))
    }

    func testParsesSwapUsageFromSysctl() throws {
        let output = """
        vm.swapusage: total = 35840.00M  used = 34746.31M  free = 1093.69M  (encrypted)
        """

        let swapUsed = MemorySampler.parseSwapFromSysctl(output)

        XCTAssertEqual(swapUsed, Int64(34_746.31 * 1024 * 1024))
    }

    func testParsesTopProcessesAndStripsPaths() throws {
        let output = """
          PID COMM                RSS
          42 /Applications/Chrome.app/Contents/MacOS/Chrome 4242424
          43 500000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer
          99 /usr/bin/python3     100000
          12 /bin/zsh             2000
        """

        let processes = MemorySampler.parseProcesses(output, ignoredNames: ["zsh"], limit: 3)

        XCTAssertEqual(processes.map(\.name), ["Chrome", "Google Chrome Helper (Renderer)", "python3"])
        XCTAssertEqual(processes.first?.residentBytes, 4_242_424 * 1024)
    }

    func testClassifiesChromeProcessKindsAndRecommendations() {
        let output = """
          10 600000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
          11 500000 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer
          12 300000 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper --type=gpu-process
          13 200000 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper --type=utility
        """

        let processes = MemorySampler.parseProcesses(output, ignoredNames: [], limit: 4)

        XCTAssertEqual(processes.map(\.kind), [.mainApp, .renderer, .gpu, .helper])
        XCTAssertTrue(processes[1].recommendation.contains("Chrome Task Manager"))
        XCTAssertTrue(processes[2].recommendation.contains("GPU"))
    }

    func testExtractsOwningAppAndAggregatesProcesses() {
        let output = """
          10 600000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
          11 500000 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer
          20 300000 /Applications/Lark.app/Contents/MacOS/Lark Helper (Renderer) --type=renderer
        """

        let snapshot = MemorySnapshot(
            totalBytes: 100,
            usedBytes: 50,
            availableBytes: 50,
            swapUsedBytes: 0,
            pressure: .normal,
            topProcesses: MemorySampler.parseProcesses(output, ignoredNames: [], limit: 10)
        )

        XCTAssertEqual(snapshot.topProcesses[0].appName, "Google Chrome")
        XCTAssertEqual(snapshot.appGroups.first?.name, "Google Chrome")
        XCTAssertEqual(snapshot.appGroups.first?.residentBytes, (600000 + 500000) * 1024)
        XCTAssertEqual(snapshot.appGroups.first?.processCount, 2)
    }

    func testDecodesOldProcessUsageWithoutKind() throws {
        let data = """
        {"pid":42,"name":"Legacy App","residentBytes":123456}
        """.data(using: .utf8)!

        let process = try JSONDecoder().decode(ProcessUsage.self, from: data)

        XCTAssertEqual(process.kind, .unknown)
        XCTAssertEqual(process.appName, "Legacy App")
    }
}
