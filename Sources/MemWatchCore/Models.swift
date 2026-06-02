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

    public init(pid: Int32, name: String, residentBytes: Int64, kind: ProcessKind = .unknown) {
        self.pid = pid
        self.name = name
        self.residentBytes = residentBytes
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case pid
        case name
        case residentBytes
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        name = try container.decode(String.self, forKey: .name)
        residentBytes = try container.decode(Int64.self, forKey: .residentBytes)
        kind = try container.decodeIfPresent(ProcessKind.self, forKey: .kind) ?? .unknown
    }

    public var recommendation: String {
        switch kind {
        case .renderer:
            return "Use Chrome Task Manager or close the related tab. Avoid killing the Chrome main process."
        case .gpu:
            return "GPU helper. Close video-heavy tabs first; restart Chrome only if graphics feel broken."
        case .mainApp:
            return "Main app process. Quit the app only when you want to close all related windows."
        case .helper:
            return "Helper process. Prefer closing the owning app or tab instead of killing it directly."
        case .unknown:
            return "Review the app before force quitting. Save work first."
        }
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
}

public struct MemorySettings: Codable, Equatable {
    public var samplingIntervalSeconds: Double
    public var warningUsedRatio: Double
    public var criticalUsedRatio: Double
    public var swapWarningBytes: Int64
    public var lowAvailableBytes: Int64
    public var consecutiveSamplesForNotification: Int
    public var notificationsEnabled: Bool
    public var ignoredProcessNames: [String]

    public init(
        samplingIntervalSeconds: Double = 15,
        warningUsedRatio: Double = 0.80,
        criticalUsedRatio: Double = 0.90,
        swapWarningBytes: Int64 = 4 * 1024 * 1024 * 1024,
        lowAvailableBytes: Int64 = 1 * 1024 * 1024 * 1024,
        consecutiveSamplesForNotification: Int = 2,
        notificationsEnabled: Bool = true,
        ignoredProcessNames: [String] = []
    ) {
        self.samplingIntervalSeconds = samplingIntervalSeconds
        self.warningUsedRatio = warningUsedRatio
        self.criticalUsedRatio = criticalUsedRatio
        self.swapWarningBytes = swapWarningBytes
        self.lowAvailableBytes = lowAvailableBytes
        self.consecutiveSamplesForNotification = consecutiveSamplesForNotification
        self.notificationsEnabled = notificationsEnabled
        self.ignoredProcessNames = ignoredProcessNames
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

    public init(level: PressureLevel, reasons: [String], shouldNotify: Bool, event: MemoryEvent?) {
        self.level = level
        self.reasons = reasons
        self.shouldNotify = shouldNotify
        self.event = event
    }
}

public extension Int64 {
    var memwatchGB: Double {
        Double(self) / 1024 / 1024 / 1024
    }
}
