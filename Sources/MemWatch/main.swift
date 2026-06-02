import AppKit
import Foundation
import MemWatchCore
import SwiftUI

let arguments = CommandLine.arguments.dropFirst()

if arguments.contains("--self-test") {
    SelfTest.run()
} else if arguments.contains("--once") {
    OnceCommand.run()
} else {
    MemWatchApp.main()
}

enum OnceCommand {
    static func run() {
        do {
            let sampler = MemorySampler()
            let snapshot = try sampler.sample()
            let analyzer = MemoryAnalyzer()
            let analysis = analyzer.analyze(snapshot: snapshot, settings: MemorySettings(notificationsEnabled: false))
            print("MemWatch sample")
            print("state: \(analysis.level.rawValue)")
            print("used: \(formatBytes(snapshot.usedBytes)) / \(formatBytes(snapshot.totalBytes)) (\(formatPercent(snapshot.usedRatio)))")
            print("available: \(formatBytes(snapshot.availableBytes))")
            print("swap: \(formatBytes(snapshot.swapUsedBytes))")
            print("pressure: \(snapshot.pressure.rawValue)")
            if !analysis.reasons.isEmpty {
                print("reasons: \(analysis.reasons.joined(separator: "; "))")
            }
            print("top processes:")
            for process in snapshot.topProcesses {
                print("- \(process.name) [\(process.pid)]: \(formatBytes(process.residentBytes))")
            }
            Foundation.exit(0)
        } catch {
            fputs("MemWatch sample failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

enum SelfTest {
    static func run() {
        var failures: [String] = []

        do {
            let total = try MemorySampler.parseTotalMemory("hw.memsize: 17179869184\n")
            expect(total == 17_179_869_184, "parseTotalMemory", &failures)

            let vm = """
            Mach Virtual Memory Statistics: (page size of 16384 bytes)
            Pages free:                               1024.
            Pages active:                             2000.
            Pages inactive:                           3000.
            Pages speculative:                        512.
            Pages wired down:                         4000.
            Pages compressed:                         1000.
            """
            let counters = try MemorySampler.parseVMStat(vm, totalMemoryBytes: 16_384 * 20_000)
            expect(counters.freeBytes == 16_384 * (1024 + 512), "parseVMStat free", &failures)
            expect(counters.usedBytes == 16_384 * (2000 + 3000 + 4000 + 1000), "parseVMStat used", &failures)

            let swap = MemorySampler.parseSwapFromSysctl("vm.swapusage: total = 35840.00M  used = 34746.31M  free = 1093.69M  (encrypted)")
            expect(swap == Int64(34_746.31 * 1024 * 1024), "parse sysctl swap", &failures)

            let processes = MemorySampler.parseProcesses("""
              PID COMM                RSS
              42 /Applications/Chrome.app/Contents/MacOS/Chrome 4242424
              43 500000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer
              99 /usr/bin/python3     100000
              12 /bin/zsh             2000
            """, ignoredNames: ["zsh"], limit: 3)
            expect(processes.map(\.name) == ["Chrome", "Google Chrome Helper (Renderer)", "python3"], "parse processes", &failures)

            let analyzer = MemoryAnalyzer()
            let snapshot = MemorySnapshot(totalBytes: 100, usedBytes: 85, availableBytes: 20, swapUsedBytes: 0, pressure: .normal, topProcesses: [])
            let first = analyzer.analyze(snapshot: snapshot, settings: MemorySettings(consecutiveSamplesForNotification: 2))
            let second = analyzer.analyze(snapshot: snapshot, settings: MemorySettings(consecutiveSamplesForNotification: 2))
            expect(first.shouldNotify == false, "first abnormal sample suppressed", &failures)
            expect(second.shouldNotify == true, "second abnormal sample notifies", &failures)
        } catch {
            failures.append(error.localizedDescription)
        }

        if failures.isEmpty {
            print("MemWatch self-test: PASS")
            Foundation.exit(0)
        } else {
            print("MemWatch self-test: FAIL")
            for failure in failures {
                print("- \(failure)")
            }
            Foundation.exit(1)
        }
    }

    private static func expect(_ condition: Bool, _ name: String, _ failures: inout [String]) {
        if !condition {
            failures.append(name)
        }
    }
}

struct MemWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = MemoryMonitor()

    var body: some Scene {
        MenuBarExtra {
            StatusPopover()
                .environmentObject(monitor)
                .frame(width: 360)
                .onAppear {
                    monitor.start()
                }
        } label: {
            Text(menuTitle)
                .foregroundStyle(color)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(monitor)
                .frame(width: 420, height: 360)
        }
    }

    private var menuTitle: String {
        guard let snapshot = monitor.snapshot else { return "MEM --" }
        return "MEM \(formatPercent(snapshot.usedRatio))"
    }

    private var color: Color {
        switch monitor.analysis.level {
        case .critical: .red
        case .warning: .orange
        case .normal: .green
        case .unknown: .secondary
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct StatusPopover: View {
    @EnvironmentObject private var monitor: MemoryMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let snapshot = monitor.snapshot {
                metrics(snapshot)
                reasons
                processList(snapshot.topProcesses)
                latestEvent
            } else {
                Text("Sampling memory...")
                    .foregroundStyle(.secondary)
            }
            controls
        }
        .padding(16)
        .onAppear {
            monitor.sampleNow()
        }
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text("MemWatch")
                .font(.headline)
            Spacer()
            Text(monitor.analysis.level.rawValue.capitalized)
                .font(.subheadline)
                .foregroundStyle(statusColor)
        }
    }

    private func metrics(_ snapshot: MemorySnapshot) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            metricRow("Used", "\(formatBytes(snapshot.usedBytes)) / \(formatBytes(snapshot.totalBytes))")
            metricRow("Available", formatBytes(snapshot.availableBytes))
            metricRow("Swap", formatBytes(snapshot.swapUsedBytes))
            metricRow("Pressure", snapshot.pressure.rawValue.capitalized)
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = monitor.snapshot?.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else if monitor.analysis.reasons.isEmpty {
                Text("No abnormal memory pattern detected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.analysis.reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.callout)
                }
            }
        }
    }

    private func processList(_ processes: [ProcessUsage]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top Processes")
                .font(.subheadline)
                .fontWeight(.semibold)
            ForEach(processes) { process in
                HStack {
                    Text(process.name)
                        .lineLimit(1)
                    Spacer()
                    Text(formatBytes(process.residentBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var latestEvent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Latest Event")
                .font(.subheadline)
                .fontWeight(.semibold)
            if let event = monitor.events.first {
                Text(event.message)
                    .font(.callout)
                    .lineLimit(3)
                Text(event.date.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No abnormal events yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button("Refresh") {
                monitor.sampleNow()
            }
            Button("Clear Events") {
                monitor.clearEvents()
            }
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }

    private var statusColor: Color {
        switch monitor.analysis.level {
        case .critical: .red
        case .warning: .orange
        case .normal: .green
        case .unknown: .secondary
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var monitor: MemoryMonitor
    @State private var ignoredText = ""

    var body: some View {
        Form {
            Section("Sampling") {
                Stepper(value: binding(\.samplingIntervalSeconds), in: 5...120, step: 5) {
                    Text("Interval: \(Int(monitor.settings.samplingIntervalSeconds)) seconds")
                }
                Toggle("Notifications", isOn: binding(\.notificationsEnabled))
            }

            Section("Thresholds") {
                Slider(value: binding(\.warningUsedRatio), in: 0.50...0.95, step: 0.01) {
                    Text("Warning")
                } minimumValueLabel: {
                    Text("50")
                } maximumValueLabel: {
                    Text("95")
                }
                Text("Warning at \(formatPercent(monitor.settings.warningUsedRatio)) used")

                Slider(value: binding(\.criticalUsedRatio), in: 0.60...0.99, step: 0.01) {
                    Text("Critical")
                } minimumValueLabel: {
                    Text("60")
                } maximumValueLabel: {
                    Text("99")
                }
                Text("Critical at \(formatPercent(monitor.settings.criticalUsedRatio)) used")
            }

            Section("Ignored Processes") {
                TextField("Chrome,node", text: $ignoredText)
                    .onSubmit { saveIgnored() }
                Button("Save Ignore List") {
                    saveIgnored()
                }
            }
        }
        .padding(20)
        .onAppear {
            ignoredText = monitor.settings.ignoredProcessNames.joined(separator: ",")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MemorySettings, Value>) -> Binding<Value> {
        Binding(
            get: { monitor.settings[keyPath: keyPath] },
            set: { value in
                monitor.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func saveIgnored() {
        let names = ignoredText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        monitor.updateSettings { $0.ignoredProcessNames = names }
    }
}
