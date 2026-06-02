import Foundation

public final class MemoryAnalyzer {
    private var consecutiveAbnormalSamples = 0
    private var lastNotifiedLevel: PressureLevel = .normal
    private var previousProcessBytes: [Int32: Int64] = [:]
    private var samplesSinceLastNotification: Int?
    private var wasAbnormal = false

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

        let growingProcess = detectGrowth(snapshot: snapshot)
        if let growingProcess {
            reasons.append("\(growingProcess.name) grew by \(formatBytes(growingProcess.deltaBytes))")
        }

        let abnormal = level >= .warning
        let didRecover = wasAbnormal && !abnormal
        consecutiveAbnormalSamples = abnormal ? consecutiveAbnormalSamples + 1 : 0

        let reachedNotificationWindow = consecutiveAbnormalSamples >= max(1, settings.consecutiveSamplesForNotification)
        let cooldownSatisfied = samplesSinceLastNotification.map { $0 >= settings.notificationCooldownSamples } ?? true
        let shouldNotify = settings.notificationsEnabled
            && abnormal
            && reachedNotificationWindow
            && (level > lastNotifiedLevel || consecutiveAbnormalSamples == settings.consecutiveSamplesForNotification || cooldownSatisfied)

        var event: MemoryEvent?
        if shouldNotify {
            lastNotifiedLevel = level
            let message = eventMessage(level: level, snapshot: snapshot, reasons: reasons)
            event = MemoryEvent(level: level, message: message, topProcesses: snapshot.topProcesses)
            samplesSinceLastNotification = 0
        } else if didRecover {
            event = MemoryEvent(level: .normal, message: "Memory pressure recovered", topProcesses: snapshot.topProcesses)
            samplesSinceLastNotification = nil
        } else if samplesSinceLastNotification != nil {
            samplesSinceLastNotification? += 1
        }

        if !abnormal {
            lastNotifiedLevel = .normal
        }

        updateProcessHistory(snapshot: snapshot)
        wasAbnormal = abnormal

        return MemoryAnalysis(level: level, reasons: reasons, shouldNotify: shouldNotify, event: event, growingProcess: growingProcess, didRecover: didRecover)
    }

    private func eventMessage(level: PressureLevel, snapshot: MemorySnapshot, reasons: [String]) -> String {
        var parts = reasons
        parts.insert("\(formatPercent(snapshot.usedRatio)) used", at: 0)
        if snapshot.swapUsedBytes > 0 {
            parts.append("\(formatBytes(snapshot.swapUsedBytes)) swap")
        }
        if let top = snapshot.topProcesses.first {
            parts.append("Top: \(top.name) \(formatBytes(top.residentBytes))")
        }
        if parts.isEmpty {
            return "Memory pressure is \(level.rawValue)"
        }
        return parts.joined(separator: ". ")
    }

    public func reset() {
        consecutiveAbnormalSamples = 0
        lastNotifiedLevel = .normal
        previousProcessBytes = [:]
        samplesSinceLastNotification = nil
        wasAbnormal = false
    }

    private func detectGrowth(snapshot: MemorySnapshot) -> ProcessGrowth? {
        let minimumGrowth = Int64(512 * 1024 * 1024)
        return snapshot.topProcesses.compactMap { process in
            guard let previous = previousProcessBytes[process.pid] else { return nil }
            let growth = process.residentBytes - previous
            guard growth >= minimumGrowth else { return nil }
            return ProcessGrowth(
                pid: process.pid,
                name: process.name,
                appName: process.appName,
                previousBytes: previous,
                currentBytes: process.residentBytes
            )
        }
        .max(by: { $0.deltaBytes < $1.deltaBytes })
    }

    private func updateProcessHistory(snapshot: MemorySnapshot) {
        previousProcessBytes = Dictionary(uniqueKeysWithValues: snapshot.topProcesses.map { ($0.pid, $0.residentBytes) })
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
