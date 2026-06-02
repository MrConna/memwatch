import Foundation

public struct MemorySampler {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ShellCommandRunner()) {
        self.runner = runner
    }

    public func sample(settings: MemorySettings = MemorySettings()) throws -> MemorySnapshot {
        let total = try Self.parseTotalMemory(runner.run("sysctl hw.memsize"))
        let counters = try Self.parseVMStat(runner.run("vm_stat"), totalMemoryBytes: total)
        let swapUsedBytes = Self.parseSwapFromSysctl((try? runner.run("sysctl vm.swapusage")) ?? "")
        let pressureLevel = Self.estimatePressure(counters: counters, swapUsedBytes: swapUsedBytes, settings: settings)
        let processes = Self.parseProcesses(
            try runner.run("ps -axo pid=,rss=,command= | sort -nrk2 | head -20"),
            ignoredNames: settings.ignoredProcessNames,
            limit: 5
        )

        return MemorySnapshot(
            totalBytes: counters.totalBytes,
            usedBytes: counters.usedBytes,
            availableBytes: counters.availableBytes,
            swapUsedBytes: swapUsedBytes,
            pressure: pressureLevel,
            topProcesses: processes
        )
    }

    public static func parseTotalMemory(_ output: String) throws -> Int64 {
        guard let match = output.firstMatch(#"hw\.memsize:\s*(\d+)"#),
              let value = Int64(match[1])
        else {
            throw ParseError(kind: "sysctl hw.memsize")
        }
        return value
    }

    public static func parseVMStat(_ output: String, totalMemoryBytes: Int64) throws -> MemoryCounters {
        guard let pageSizeMatch = output.firstMatch(#"page size of\s+(\d+)\s+bytes"#),
              let pageSize = Int64(pageSizeMatch[1])
        else {
            throw ParseError(kind: "vm_stat page size")
        }

        func pages(_ label: String) -> Int64 {
            guard let match = output.firstMatch(#"\#(label):\s+(\d+)\."#),
                  let value = Int64(match[1])
            else { return 0 }
            return value
        }

        let freePages = pages("Pages free")
        let speculativePages = pages("Pages speculative")
        let activePages = pages("Pages active")
        let inactivePages = pages("Pages inactive")
        let wiredPages = pages("Pages wired down")
        let compressedPages = pages("Pages compressed")

        let freeBytes = (freePages + speculativePages) * pageSize
        let availableBytes = (freePages + speculativePages + inactivePages) * pageSize
        let usedBytes = (activePages + inactivePages + wiredPages + compressedPages) * pageSize

        return MemoryCounters(
            pageSize: pageSize,
            totalBytes: totalMemoryBytes,
            freeBytes: freeBytes,
            usedBytes: min(usedBytes, totalMemoryBytes),
            availableBytes: min(availableBytes, totalMemoryBytes)
        )
    }

    public static func parseMemoryPressure(_ output: String) -> PressureSummary {
        let lowercased = output.lowercased()
        let level: PressureLevel
        if lowercased.contains("critical") || lowercased.contains("urgent") {
            level = .critical
        } else if lowercased.contains("warn") {
            level = .warning
        } else if lowercased.contains("normal") {
            level = .normal
        } else {
            level = .unknown
        }

        let swap = parseSwapBytes(output)
        return PressureSummary(level: level, swapUsedBytes: swap)
    }

    public static func parseSwapFromSysctl(_ output: String) -> Int64 {
        parseSwapBytes(output)
    }

    public static func estimatePressure(counters: MemoryCounters, swapUsedBytes: Int64, settings: MemorySettings) -> PressureLevel {
        let usedRatio = counters.totalBytes > 0 ? Double(counters.usedBytes) / Double(counters.totalBytes) : 0
        if usedRatio >= settings.criticalUsedRatio {
            return .critical
        }
        if usedRatio >= settings.warningUsedRatio ||
            swapUsedBytes >= settings.swapWarningBytes ||
            counters.availableBytes <= settings.lowAvailableBytes {
            return .warning
        }
        return .normal
    }

    public static func parseProcesses(_ output: String, ignoredNames: [String], limit: Int) -> [ProcessUsage] {
        let ignored = Set(ignoredNames.map { $0.lowercased() })
        let rows = output.split(separator: "\n").compactMap { rawLine -> ProcessUsage? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.uppercased().hasPrefix("PID ") else { return nil }

            let pid: Int32
            let rssKB: Int64
            let command: String

            if let actualMatch = line.firstMatch(#"^(\d+)\s+(\d+)\s+(.+)$"#),
               let parsedPID = Int32(actualMatch[1]),
               let parsedRSS = Int64(actualMatch[2]) {
                pid = parsedPID
                rssKB = parsedRSS
                command = actualMatch[3]
            } else if let fixtureMatch = line.firstMatch(#"^(\d+)\s+(.+)\s+(\d+)$"#),
                      let parsedPID = Int32(fixtureMatch[1]),
                      let parsedRSS = Int64(fixtureMatch[3]) {
                pid = parsedPID
                rssKB = parsedRSS
                command = fixtureMatch[2]
            } else {
                return nil
            }

            let name = normalizeProcessName(command)
            guard !ignored.contains(name.lowercased()) else { return nil }
            return ProcessUsage(pid: pid, name: name, residentBytes: rssKB * 1024, kind: classifyProcess(command: command, name: name))
        }

        return rows
            .sorted { $0.residentBytes > $1.residentBytes }
            .prefix(limit)
            .map { $0 }
    }

    private static func parseSwapBytes(_ output: String) -> Int64 {
        if let kilobytes = output.firstMatch(#"(?i)Swap:.*?(\d+)\s*K(?:B)?\s+used"#).flatMap({ Int64($0[1]) }) {
            return kilobytes * 1024
        }

        if let megabytes = output.firstMatch(#"(?i)used\s*=\s*([0-9.]+)M"#).flatMap({ Double($0[1]) }) {
            return Int64(megabytes * 1024 * 1024)
        }

        if let gigabytes = output.firstMatch(#"(?i)used\s*=\s*([0-9.]+)G"#).flatMap({ Double($0[1]) }) {
            return Int64(gigabytes * 1024 * 1024 * 1024)
        }

        return 0
    }

    private static func normalizeProcessName(_ command: String) -> String {
        var trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if let argumentRange = trimmed.range(of: " --") {
            trimmed = String(trimmed[..<argumentRange.lowerBound])
        }

        if let appRange = trimmed.range(of: ".app/Contents/MacOS/") {
            let executable = String(trimmed[appRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !executable.isEmpty {
                return executable
            }
        }

        let lastPathComponent = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let firstToken = lastPathComponent.split(separator: " ").first.map(String.init)
        return firstToken?.isEmpty == false ? firstToken! : lastPathComponent
    }

    private static func classifyProcess(command: String, name: String) -> ProcessKind {
        let lowercasedCommand = command.lowercased()
        let lowercasedName = name.lowercased()

        if lowercasedCommand.contains("--type=renderer") || lowercasedName.contains("renderer") {
            return .renderer
        }
        if lowercasedCommand.contains("--type=gpu-process") {
            return .gpu
        }
        if lowercasedName == "google chrome" || lowercasedCommand.hasSuffix("/google chrome") {
            return .mainApp
        }
        if lowercasedCommand.contains("--type=") || lowercasedName.contains("helper") {
            return .helper
        }
        return .unknown
    }
}

public struct ParseError: Error, LocalizedError {
    public var kind: String

    public var errorDescription: String? {
        "Could not parse \(kind)"
    }
}

private extension String {
    func firstMatch(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let swiftRange = Range(match.range(at: index), in: self) else { return nil }
            return String(self[swiftRange])
        }
    }
}
