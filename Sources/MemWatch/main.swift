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
            let snapshot = try MemorySampler().sample()
            let analysis = MemoryAnalyzer().analyze(snapshot: snapshot, settings: MemorySettings(notificationsEnabled: false))
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
                print("- \(process.name) [\(process.pid)] \(process.kind.rawValue): \(formatBytes(process.residentBytes))")
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
                .frame(width: 430)
                .onAppear {
                    monitor.start()
                }
        } label: {
            Text(menuTitle)
                .foregroundStyle(menuColor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(monitor)
                .frame(width: 460, height: 460)
        }
    }

    private var menuTitle: String {
        guard let snapshot = monitor.snapshot else { return "MEM --" }
        return "MEM \(formatPercent(snapshot.usedRatio))"
    }

    private var menuColor: Color {
        switch monitor.analysis.level {
        case .critical: .red
        case .warning: .orange
        case .normal: .green
        case .unknown: .secondary
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        showWelcomeIfNeeded()
    }

    private func showWelcomeIfNeeded() {
        let key = "memwatch.welcome.v2.shown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MemWatch"
        window.contentView = NSHostingView(rootView: WelcomeView())
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = window
    }
}

struct StatusPopover: View {
    @EnvironmentObject private var monitor: MemoryMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let snapshot = monitor.snapshot {
                    memorySummary(snapshot)
                    metricGrid(snapshot)
                    trendLine
                    diagnosis
                    processList(snapshot.topProcesses)
                    eventList
                } else {
                    loadingState
                }
                controls
            }
            .padding(16)
        }
        .frame(maxHeight: 620)
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
            Text(statusTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.14))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
    }

    private func memorySummary(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatPercent(snapshot.usedRatio))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("memory used")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.sampledAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: min(max(snapshot.usedRatio, 0), 1))
                .tint(statusColor)

            Text(summaryLine(snapshot))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func metricGrid(_ snapshot: MemorySnapshot) -> some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                MetricTile(title: "Used", value: formatBytes(snapshot.usedBytes))
                MetricTile(title: "Available", value: formatBytes(snapshot.availableBytes))
            }
            GridRow {
                MetricTile(title: "Swap", value: formatBytes(snapshot.swapUsedBytes))
                MetricTile(title: "Pressure", value: snapshot.pressure.rawValue.capitalized)
            }
        }
    }

    private var diagnosis: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Diagnosis")
            if let error = monitor.snapshot?.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else if monitor.analysis.reasons.isEmpty {
                Text("Memory looks healthy. No abnormal pattern detected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.analysis.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(statusColor)
                }
            }
        }
    }

    private var trendLine: some View {
        HStack(spacing: 8) {
            Image(systemName: monitor.abnormalSince == nil ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .foregroundStyle(monitor.abnormalSince == nil ? .green : statusColor)
            Text(trendText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func processList(_ processes: [ProcessUsage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Top Processes")
            ForEach(processes) { process in
                ProcessRow(process: process)
            }
        }
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Recent Events")
            if monitor.events.isEmpty {
                Text("No abnormal events recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.events.prefix(3)) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(event.level.rawValue.capitalized)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(event.level == .critical ? .red : .orange)
                            Spacer()
                            Text(event.date.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(event.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Button {
                monitor.sampleNow()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button {
                monitor.clearEvents()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            Spacer()
            Button {
                openLoginItems()
            } label: {
                Label("Login Items", systemImage: "gear")
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.borderless)
    }

    private var loadingState: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Sampling memory...")
                .foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        switch monitor.analysis.level {
        case .critical: "Critical"
        case .warning: "Warning"
        case .normal: "Normal"
        case .unknown: "Sampling"
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

    private func summaryLine(_ snapshot: MemorySnapshot) -> String {
        if monitor.analysis.level == .normal {
            return "\(formatBytes(snapshot.availableBytes)) available, \(formatBytes(snapshot.swapUsedBytes)) swap."
        }
        return monitor.analysis.reasons.first ?? "Memory pressure needs attention."
    }

    private var trendText: String {
        if let abnormalSince = monitor.abnormalSince {
            return "Abnormal since \(abnormalSince.formatted(date: .omitted, time: .shortened))."
        }
        if let recoveredAt = monitor.lastRecoveredAt {
            return "Recovered at \(recoveredAt.formatted(date: .omitted, time: .shortened))."
        }
        return "No sustained abnormal pressure in this session."
    }
}

struct SettingsView: View {
    @EnvironmentObject private var monitor: MemoryMonitor
    @State private var ignoredText = ""
    @State private var preset: MemorySensitivityPreset = .balanced
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Preset") {
                Picker("Sensitivity", selection: $preset) {
                    ForEach([MemorySensitivityPreset.relaxed, .balanced, .sensitive], id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                Button("Apply \(preset.title)") {
                    applyPreset(preset)
                }
            }

            Section("Sampling") {
                Stepper(value: binding(\.samplingIntervalSeconds), in: 5...120, step: 5) {
                    Text("Interval: \(Int(monitor.settings.samplingIntervalSeconds)) seconds")
                }
                Toggle("Notifications", isOn: binding(\.notificationsEnabled))
            }

            DisclosureGroup("Advanced Thresholds", isExpanded: $showAdvanced) {
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

            Section("Install") {
                Button("Open Login Items Settings") {
                    openLoginItems()
                }
                Text("Add MemWatch to Login Items if you want it to start with macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func applyPreset(_ preset: MemorySensitivityPreset) {
        let notifications = monitor.settings.notificationsEnabled
        let ignored = monitor.settings.ignoredProcessNames
        var settings = preset.settings
        settings.notificationsEnabled = notifications
        settings.ignoredProcessNames = ignored
        monitor.settings = settings
    }

    private func saveIgnored() {
        let names = ignoredText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        monitor.updateSettings { $0.ignoredProcessNames = names }
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "memorychip")
                    .font(.system(size: 34))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MemWatch is running")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Look for MEM in the menu bar.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Click MEM to inspect memory pressure and top processes.", systemImage: "menubar.rectangle")
                Label("Use Chrome Task Manager for renderer processes.", systemImage: "safari")
                Label("Add MemWatch to Login Items to start it with macOS.", systemImage: "power")
            }
            .font(.callout)

            Spacer()

            HStack {
                Button("Open Login Items") {
                    openLoginItems()
                }
                Spacer()
                Button("Got It") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}

struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct ProcessRow: View {
    let process: ProcessUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("\(process.kind.rawValue) · PID \(process.pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatBytes(process.residentBytes))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            Text(process.recommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

func openLoginItems() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
        NSWorkspace.shared.open(url)
    }
}
