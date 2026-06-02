import Foundation

public final class MemoryAnalyzer {
    private var consecutiveAbnormalSamples = 0
    private var lastNotifiedLevel: PressureLevel = .normal

    public init() {}

    public func analyze(snapshot: MemorySnapshot, settings: MemorySettings) -> MemoryAnalysis {
        var level = snapshot.pressure == .unknown ? .normal : snapshot.pressure
        var reasons: [String] = []

        if snapshot.pressure >= .warning {
            reasons.append("macOS memory pressure is \(snapshot.pressure.rawValue)")
        }

        if snapshot.usedRatio >= settings.criticalUsedRatio {
            level = .critical
            reasons.append("used memory is \(formatPercent(snapshot.usedRatio))")
        } else if snapshot.usedRatio >= settings.warningUsedRatio {
            level = max(level, .warning)
            reasons.append("used memory is \(formatPercent(snapshot.usedRatio))")
        }

        if snapshot.swapUsedBytes >= settings.swapWarningBytes {
            level = max(level, .warning)
            reasons.append("swap is \(formatBytes(snapshot.swapUsedBytes))")
        }

        if snapshot.availableBytes <= settings.lowAvailableBytes {
            level = max(level, .warning)
            reasons.append("available memory is \(formatBytes(snapshot.availableBytes))")
        }

        if let top = snapshot.topProcesses.first, top.residentBytes >= 2 * 1024 * 1024 * 1024 {
            reasons.append("\(top.name) uses \(formatBytes(top.residentBytes))")
        }

        let abnormal = level >= .warning
        consecutiveAbnormalSamples = abnormal ? consecutiveAbnormalSamples + 1 : 0

        let reachedNotificationWindow = consecutiveAbnormalSamples >= max(1, settings.consecutiveSamplesForNotification)
        let shouldNotify = settings.notificationsEnabled
            && abnormal
            && reachedNotificationWindow
            && (level > lastNotifiedLevel || consecutiveAbnormalSamples == settings.consecutiveSamplesForNotification)

        var event: MemoryEvent?
        if shouldNotify {
            lastNotifiedLevel = level
            let message = reasons.isEmpty ? "Memory pressure is \(level.rawValue)" : reasons.joined(separator: ". ")
            event = MemoryEvent(level: level, message: message, topProcesses: snapshot.topProcesses)
        }

        if !abnormal {
            lastNotifiedLevel = .normal
        }

        return MemoryAnalysis(level: level, reasons: reasons, shouldNotify: shouldNotify, event: event)
    }

    public func reset() {
        consecutiveAbnormalSamples = 0
        lastNotifiedLevel = .normal
    }
}

public func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1024 / 1024 / 1024
    if gb >= 1 {
        return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1024 / 1024
    return String(format: "%.0f MB", mb)
}

public func formatPercent(_ ratio: Double) -> String {
    String(format: "%.0f%%", ratio * 100)
}

