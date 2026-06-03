import Foundation

public enum PressureLevel: String, Codable, Equatable, Comparable {
    case normal
    case warning
    case critical
    case unknown

    public static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ level: PressureLevel) -> Int {
        switch level {
        case .unknown: 0
        case .normal: 1
        case .warning: 2
        case .critical: 3
        }
    }
}

public struct MemoryCounters: Equatable {
    public var pageSize: Int64
    public var totalBytes: Int64
    public var freeBytes: Int64
    public var usedBytes: Int64
    public var availableBytes: Int64

    public init(pageSize: Int64, totalBytes: Int64, freeBytes: Int64, usedBytes: Int64, availableBytes: Int64) {
        self.pageSize = pageSize
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }
}

public struct PressureSummary: Equatable {
    public var level: PressureLevel
    public var swapUsedBytes: Int64

    public init(level: PressureLevel, swapUsedBytes: Int64) {
        self.level = level
        self.swapUsedBytes = swapUsedBytes
    }
}

public struct ProcessUsage: Identifiable, Codable, Equatable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var name: String
    public var residentBytes: Int64
    public var kind: ProcessKind
    public var appName: String

    public init(pid: Int32, name: String, residentBytes: Int64, kind: ProcessKind = .unknown, appName: String? = nil) {
        self.pid = pid
        self.name = name
        self.residentBytes = residentBytes
        self.kind = kind
        self.appName = appName ?? name
    }

    private enum CodingKeys: String, CodingKey {
        case pid
        case name
        case residentBytes
        case kind
        case appName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        name = try container.decode(String.self, forKey: .name)
        residentBytes = try container.decode(Int64.self, forKey: .residentBytes)
        kind = try container.decodeIfPresent(ProcessKind.self, forKey: .kind) ?? .unknown
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? name
    }

    public var recommendation: String {
        switch kind {
        case .renderer:
            if appName.localizedCaseInsensitiveContains("Chrome") {
                return "Use Chrome Task Manager or close the related tab. Avoid killing the Chrome main process."
            }
            return "Renderer process. Close the related \(appName) tab, window, or workspace before force quitting helpers."
        case .gpu:
            return "GPU helper. Close video-heavy \(appName) tabs or windows first; restart \(appName) only if graphics feel broken."
        case .mainApp:
            return "Main app process. Quit the app only when you want to close all related windows."
        case .helper:
            return "Helper process. Prefer closing the owning app or tab instead of killing it directly."
        case .unknown:
            return "Review the app before force quitting. Save work first."
        }
    }
}

public struct AppMemoryGroup: Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var residentBytes: Int64
    public var processCount: Int
    public var topProcess: ProcessUsage

    public init(name: String, residentBytes: Int64, processCount: Int, topProcess: ProcessUsage) {
        self.name = name
        self.residentBytes = residentBytes
        self.processCount = processCount
        self.topProcess = topProcess
    }
}

public enum ProcessKind: String, Codable, Equatable, CaseIterable {
    case mainApp = "Main App"
    case renderer = "Renderer"
    case gpu = "GPU"
    case helper = "Helper"
    case unknown = "Unknown"
}

public struct MemorySnapshot: Equatable {
    public var sampledAt: Date
    public var totalBytes: Int64
    public var usedBytes: Int64
    public var availableBytes: Int64
    public var swapUsedBytes: Int64
    public var pressure: PressureLevel
    public var topProcesses: [ProcessUsage]
    public var errorMessage: String?

    public init(
        sampledAt: Date = Date(),
        totalBytes: Int64,
        usedBytes: Int64,
        availableBytes: Int64,
        swapUsedBytes: Int64,
        pressure: PressureLevel,
        topProcesses: [ProcessUsage],
        errorMessage: String? = nil
    ) {
        self.sampledAt = sampledAt
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
        self.topProcesses = topProcesses
        self.errorMessage = errorMessage
    }

    public var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public var appGroups: [AppMemoryGroup] {
        let groups = Dictionary(grouping: topProcesses, by: \.appName)
        return groups.compactMap { name, processes in
            guard let top = processes.max(by: { $0.residentBytes < $1.residentBytes }) else { return nil }
            let total = processes.reduce(Int64(0)) { $0 + $1.residentBytes }
            return AppMemoryGroup(name: name, residentBytes: total, processCount: processes.count, topProcess: top)
        }
        .sorted { $0.residentBytes > $1.residentBytes }
    }
}

public struct MemorySettings: Codable, Equatable {
    public var samplingIntervalSeconds: Double
    public var warningUsedRatio: Double
    public var criticalUsedRatio: Double
    public var swapWarningBytes: Int64
    public var lowAvailableBytes: Int64
    public var consecutiveSamplesForNotification: Int
    public var notificationCooldownSamples: Int
    public var notificationsEnabled: Bool
    public var ignoredProcessNames: [String]

    public init(
        samplingIntervalSeconds: Double = 15,
        warningUsedRatio: Double = 0.80,
        criticalUsedRatio: Double = 0.90,
        swapWarningBytes: Int64 = 4 * 1024 * 1024 * 1024,
        lowAvailableBytes: Int64 = 1 * 1024 * 1024 * 1024,
        consecutiveSamplesForNotification: Int = 2,
        notificationCooldownSamples: Int = 8,
        notificationsEnabled: Bool = true,
        ignoredProcessNames: [String] = []
    ) {
        self.samplingIntervalSeconds = samplingIntervalSeconds
        self.warningUsedRatio = warningUsedRatio
        self.criticalUsedRatio = criticalUsedRatio
        self.swapWarningBytes = swapWarningBytes
        self.lowAvailableBytes = lowAvailableBytes
        self.consecutiveSamplesForNotification = consecutiveSamplesForNotification
        self.notificationCooldownSamples = notificationCooldownSamples
        self.notificationsEnabled = notificationsEnabled
        self.ignoredProcessNames = ignoredProcessNames
    }

    private enum CodingKeys: String, CodingKey {
        case samplingIntervalSeconds
        case warningUsedRatio
        case criticalUsedRatio
        case swapWarningBytes
        case lowAvailableBytes
        case consecutiveSamplesForNotification
        case notificationCooldownSamples
        case notificationsEnabled
        case ignoredProcessNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        samplingIntervalSeconds = try container.decode(Double.self, forKey: .samplingIntervalSeconds)
        warningUsedRatio = try container.decode(Double.self, forKey: .warningUsedRatio)
        criticalUsedRatio = try container.decode(Double.self, forKey: .criticalUsedRatio)
        swapWarningBytes = try container.decode(Int64.self, forKey: .swapWarningBytes)
        lowAvailableBytes = try container.decode(Int64.self, forKey: .lowAvailableBytes)
        consecutiveSamplesForNotification = try container.decode(Int.self, forKey: .consecutiveSamplesForNotification)
        notificationCooldownSamples = try container.decodeIfPresent(Int.self, forKey: .notificationCooldownSamples) ?? 8
        notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        ignoredProcessNames = try container.decode([String].self, forKey: .ignoredProcessNames)
    }
}

public enum MemorySensitivityPreset: String, Codable, CaseIterable, Identifiable {
    case relaxed
    case balanced
    case sensitive
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .relaxed: "Relaxed"
        case .balanced: "Balanced"
        case .sensitive: "Sensitive"
        case .custom: "Custom"
        }
    }

    public var settings: MemorySettings {
        switch self {
        case .relaxed:
            MemorySettings(
                samplingIntervalSeconds: 30,
                warningUsedRatio: 0.88,
                criticalUsedRatio: 0.95,
                swapWarningBytes: 8 * 1024 * 1024 * 1024,
                lowAvailableBytes: 512 * 1024 * 1024,
                consecutiveSamplesForNotification: 3
            )
        case .balanced:
            MemorySettings()
        case .sensitive:
            MemorySettings(
                samplingIntervalSeconds: 10,
                warningUsedRatio: 0.70,
                criticalUsedRatio: 0.85,
                swapWarningBytes: 2 * 1024 * 1024 * 1024,
                lowAvailableBytes: 2 * 1024 * 1024 * 1024,
                consecutiveSamplesForNotification: 2
            )
        case .custom:
            MemorySettings()
        }
    }
}

public struct MemoryEvent: Identifiable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    public var level: PressureLevel
    public var message: String
    public var topProcesses: [ProcessUsage]

    public init(id: UUID = UUID(), date: Date = Date(), level: PressureLevel, message: String, topProcesses: [ProcessUsage]) {
        self.id = id
        self.date = date
        self.level = level
        self.message = message
        self.topProcesses = topProcesses
    }
}

public struct MemoryAnalysis: Equatable {
    public var level: PressureLevel
    public var reasons: [String]
    public var shouldNotify: Bool
    public var event: MemoryEvent?
    public var growingProcess: ProcessGrowth?
    public var didRecover: Bool

    public init(level: PressureLevel, reasons: [String], shouldNotify: Bool, event: MemoryEvent?, growingProcess: ProcessGrowth? = nil, didRecover: Bool = false) {
        self.level = level
        self.reasons = reasons
        self.shouldNotify = shouldNotify
        self.event = event
        self.growingProcess = growingProcess
        self.didRecover = didRecover
    }
}

public struct ProcessGrowth: Equatable {
    public var pid: Int32
    public var name: String
    public var appName: String
    public var previousBytes: Int64
    public var currentBytes: Int64

    public init(pid: Int32, name: String, appName: String, previousBytes: Int64, currentBytes: Int64) {
        self.pid = pid
        self.name = name
        self.appName = appName
        self.previousBytes = previousBytes
        self.currentBytes = currentBytes
    }

    public var deltaBytes: Int64 {
        currentBytes - previousBytes
    }
}

public struct MemoryAction: Identifiable, Equatable {
    public var id: String { title }
    public var title: String
    public var detail: String
    public var systemImage: String

    public init(title: String, detail: String, systemImage: String) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }
}

public enum ProcessControlActionKind: String, Equatable {
    case activateApp
    case quitApp
    case forceQuitProcess
}

public struct ProcessControlAction: Identifiable, Equatable {
    public var id: String { kind.rawValue }
    public var kind: ProcessControlActionKind
    public var title: String
    public var detail: String
    public var systemImage: String
    public var requiresConfirmation: Bool

    public init(
        kind: ProcessControlActionKind,
        title: String,
        detail: String,
        systemImage: String,
        requiresConfirmation: Bool
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.requiresConfirmation = requiresConfirmation
    }
}

public enum ProcessControl {
    public static func actions(for process: ProcessUsage) -> [ProcessControlAction] {
        [
            ProcessControlAction(
                kind: .activateApp,
                title: "Show \(process.appName)",
                detail: "Bring the owning app forward so you can close a tab, window, or document yourself.",
                systemImage: "macwindow",
                requiresConfirmation: false
            ),
            ProcessControlAction(
                kind: .quitApp,
                title: "Quit \(process.appName)",
                detail: "Ask \(process.appName) to quit normally. This can close all related windows, so save work first.",
                systemImage: "xmark.circle",
                requiresConfirmation: true
            ),
            ProcessControlAction(
                kind: .forceQuitProcess,
                title: "Force Quit PID \(process.pid)",
                detail: "Immediately end PID \(process.pid). Use this only after saving work or when the process is stuck.",
                systemImage: "exclamationmark.octagon",
                requiresConfirmation: true
            )
        ]
    }
}

public extension Int64 {
    var memwatchGB: Double {
        Double(self) / 1024 / 1024 / 1024
    }
}

public enum MenuStatus {
    public static func title(snapshot: MemorySnapshot?, analysis: MemoryAnalysis) -> String {
        guard let snapshot else { return "MEM --" }
        if analysis.level == .critical {
            return "MEM !!"
        }
        if snapshot.swapUsedBytes >= 1024 * 1024 * 1024 {
            return "SWAP \(Int(round(snapshot.swapUsedBytes.memwatchGB)))G"
        }
        if analysis.growingProcess != nil {
            return "MEM UP"
        }
        return "MEM \(formatPercent(snapshot.usedRatio))"
    }
}

public enum MemoryGuidance {
    public static func actions(snapshot: MemorySnapshot, analysis: MemoryAnalysis) -> [MemoryAction] {
        var actions: [MemoryAction] = []
        let needsCleanup = analysis.level >= .warning || snapshot.swapUsedBytes >= 1024 * 1024 * 1024 || analysis.growingProcess != nil

        guard needsCleanup else {
            return [
                MemoryAction(
                    title: "No urgent cleanup",
                    detail: "Memory looks stable. Keep watching if the menu bar changes to SWAP, MEM UP, or MEM !!.",
                    systemImage: "checkmark.circle"
                )
            ]
        }

        if let topGroup = snapshot.appGroups.first {
            actions.append(
                MemoryAction(
                    title: "Save work first",
                    detail: "\(topGroup.name) could free about \(formatBytes(topGroup.residentBytes)) if you quit or restart it. Save files and drafts before closing.",
                    systemImage: "square.and.pencil"
                )
            )
        } else {
            actions.append(
                MemoryAction(
                    title: "Save work first",
                    detail: "Save files and drafts before quitting apps or force quitting processes.",
                    systemImage: "square.and.pencil"
                )
            )
        }

        if let chromeRenderer = snapshot.topProcesses.first(where: { process in
            process.kind == .renderer
                && process.appName.localizedCaseInsensitiveContains("Chrome")
                && process.residentBytes >= 512 * 1024 * 1024
        }) {
            actions.append(
                MemoryAction(
                    title: "Close heavy Chrome tabs",
                    detail: "\(chromeRenderer.name) uses \(formatBytes(chromeRenderer.residentBytes)). Open Chrome Task Manager from Chrome > Window > Task Manager, then close the heaviest tab.",
                    systemImage: "rectangle.on.rectangle"
                )
            )
        }

        if snapshot.swapUsedBytes >= 1024 * 1024 * 1024 || analysis.level >= .warning {
            actions.append(
                MemoryAction(
                    title: "Open Activity Monitor",
                    detail: "Sort by Memory, inspect the top apps, then quit only apps you recognize and do not need right now.",
                    systemImage: "gauge.with.dots.needle.67percent"
                )
            )
        }

        if let growing = analysis.growingProcess {
            actions.append(
                MemoryAction(
                    title: "Watch growing process",
                    detail: "\(growing.name) grew by \(formatBytes(growing.deltaBytes)). Restart \(growing.appName) if it keeps climbing after you save work.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            )
        }

        return actions
    }
}

public enum DiagnosticReport {
    public static func text(snapshot: MemorySnapshot, analysis: MemoryAnalysis) -> String {
        var lines: [String] = [
            "MemWatch Diagnostic Report",
            "Sampled At: \(snapshot.sampledAt.formatted(.iso8601))",
            "State: \(analysis.level.rawValue)",
            "Used: \(formatBytes(snapshot.usedBytes)) / \(formatBytes(snapshot.totalBytes)) (\(formatPercent(snapshot.usedRatio)))",
            "Available: \(formatBytes(snapshot.availableBytes))",
            "Swap: \(formatBytes(snapshot.swapUsedBytes))",
            "Pressure: \(snapshot.pressure.rawValue)"
        ]

        if !analysis.reasons.isEmpty {
            lines.append("")
            lines.append("Reasons:")
            lines.append(contentsOf: analysis.reasons.map { "- \($0)" })
        }

        let actions = MemoryGuidance.actions(snapshot: snapshot, analysis: analysis)
        if !actions.isEmpty {
            lines.append("")
            lines.append("How to Free Memory:")
            lines.append(contentsOf: actions.map { "- \($0.title): \($0.detail)" })
        }

        let groups = Array(snapshot.appGroups.prefix(5))
        if !groups.isEmpty {
            lines.append("")
            lines.append("Top Apps:")
            lines.append(contentsOf: groups.map { group in
                "- \(group.name): \(formatBytes(group.residentBytes)) across \(group.processCount) process(es)"
            })
        }

        let processes = Array(snapshot.topProcesses.prefix(8))
        if !processes.isEmpty {
            lines.append("")
            lines.append("Top Processes:")
            for process in processes {
                lines.append("- \(process.name) [\(process.pid)] \(process.kind.rawValue): \(formatBytes(process.residentBytes))")
                lines.append("  Recommendation: \(process.recommendation)")
            }
        }

        if let growing = analysis.growingProcess {
            lines.append("")
            lines.append("Growth:")
            lines.append("- \(growing.name) grew by \(formatBytes(growing.deltaBytes))")
        }

        lines.append("")
        lines.append("Generated by MemWatch. Save work before quitting or force quitting apps.")
        return lines.joined(separator: "\n")
    }
}
