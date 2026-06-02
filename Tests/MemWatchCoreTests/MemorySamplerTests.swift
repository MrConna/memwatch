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
}
