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
            print("top apps:")
            for group in snapshot.appGroups.prefix(5) {
                print("- \(group.name): \(formatBytes(group.residentBytes)) across \(group.processCount) process(es)")
            }
            print("top processes:")
            for process in snapshot.topProcesses.prefix(5) {
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
                .frame(width: 360)
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
        MenuStatus.title(snapshot: monitor.snapshot, analysis: monitor.analysis)
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
    @State private var settingsWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let snapshot = monitor.snapshot {
                memorySummary(snapshot)
                metricGrid(snapshot)
                nextStep(snapshot)
                appList(Array(snapshot.appGroups.prefix(3)))
            } else {
                loadingState
            }
            Divider()
            controls
        }
        .padding(14)
        .onAppear {
            monitor.sampleNow()
        }
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text("MemWatch")
                .font(.headline)
            Spacer()
            Label(statusTitle, systemImage: statusIcon)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
                .labelStyle(.titleAndIcon)
        }
    }

    private func memorySummary(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatPercent(snapshot.usedRatio))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("used")
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatBytes(snapshot.availableBytes))
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                    Text("available")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: min(max(snapshot.usedRatio, 0), 1))
                .tint(statusColor)
                .accessibilityLabel("Memory used")
                .accessibilityValue(formatPercent(snapshot.usedRatio))

            Text(summaryLine(snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func metricGrid(_ snapshot: MemorySnapshot) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                metricText("Used", formatBytes(snapshot.usedBytes))
                metricText("Available", formatBytes(snapshot.availableBytes))
            }
            GridRow {
                metricText("Swap", formatBytes(snapshot.swapUsedBytes))
                metricText("Pressure", snapshot.pressure.rawValue.capitalized)
            }
        }
    }

    private func metricText(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func nextStep(_ snapshot: MemorySnapshot) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let error = monitor.snapshot?.errorMessage {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Image(systemName: nextStepIcon(snapshot))
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nextStepTitle(snapshot))
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(nextStepDetail(snapshot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func appList(_ groups: [AppMemoryGroup]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Top Apps")
            ForEach(groups) { group in
                AppGroupRow(group: group)
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
            .help("Refresh")
            if !monitor.events.isEmpty {
                Button {
                    monitor.clearEvents()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear events")
            }
            Spacer()
            Button {
                openSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .help("Settings")
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .help("Quit")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
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

    private var statusIcon: String {
        switch monitor.analysis.level {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .normal: "checkmark.circle.fill"
        case .unknown: "circle.dotted"
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
            return "\(formatBytes(snapshot.swapUsedBytes)) swap. Last checked \(snapshot.sampledAt.formatted(date: .omitted, time: .shortened))."
        }
        return monitor.analysis.reasons.first ?? "Memory pressure needs attention."
    }

    private func nextStepIcon(_ snapshot: MemorySnapshot) -> String {
        if monitor.analysis.didRecover {
            return "arrow.down.heart.fill"
        }
        if monitor.analysis.level >= .warning {
            return "wrench.and.screwdriver.fill"
        }
        if monitor.analysis.growingProcess != nil {
            return "chart.line.uptrend.xyaxis"
        }
        if let top = snapshot.topProcesses.first, top.kind == .renderer, top.residentBytes >= 1024 * 1024 * 1024 {
            return "safari.fill"
        }
        return "checkmark.circle.fill"
    }

    private func nextStepTitle(_ snapshot: MemorySnapshot) -> String {
        if monitor.analysis.didRecover {
            return "Recovered"
        }
        if monitor.analysis.level >= .warning {
            return "Needs attention"
        }
        if monitor.analysis.growingProcess != nil {
            return "Growing process"
        }
        if let top = snapshot.topProcesses.first, top.kind == .renderer, top.residentBytes >= 1024 * 1024 * 1024 {
            return "Largest tab process"
        }
        return "Looks healthy"
    }

    private func nextStepDetail(_ snapshot: MemorySnapshot) -> String {
        if monitor.analysis.didRecover {
            return "Memory pressure returned to normal."
        }
        if let reason = monitor.analysis.reasons.first {
            return reason
        }
        if let growing = monitor.analysis.growingProcess {
            return "\(growing.name) grew by \(formatBytes(growing.deltaBytes)). Watch \(growing.appName) first."
        }
        if let top = snapshot.topProcesses.first, top.kind == .renderer, top.residentBytes >= 1024 * 1024 * 1024 {
            return "\(top.name) uses \(formatBytes(top.residentBytes)). Use the browser task manager if it grows."
        }
        return "No action needed right now."
    }

    private func openSettingsWindow() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MemWatch Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView().environmentObject(monitor))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
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

            Section("Startup") {
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
                    Text("Click MEM in the menu bar.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Check memory pressure without opening Activity Monitor.", systemImage: "gauge.with.dots.needle.67percent")
                Label("Renderer rows usually point to browser tabs.", systemImage: "rectangle.on.rectangle")
                Label("Use Settings for thresholds and startup behavior.", systemImage: "gear")
            }
            .font(.callout)

            Spacer()

            HStack {
                Button("Login Items") {
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

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 2)
    }
}

struct AppGroupRow: View {
    let group: AppMemoryGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(group.processCount) processes · top \(group.topProcess.kind.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(formatBytes(group.residentBytes))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProcessRow: View {
    let process: ProcessUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("\(process.kind.rawValue) · PID \(process.pid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(formatBytes(process.residentBytes))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            if process.kind == .renderer || process.kind == .gpu {
                Text(shortRecommendation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var shortRecommendation: String {
        switch process.kind {
        case .renderer:
            return "Close the related tab or use Chrome Task Manager."
        case .gpu:
            return "Close video-heavy tabs before restarting Chrome."
        default:
            return process.recommendation
        }
    }
}

func openLoginItems() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
        NSWorkspace.shared.open(url)
    }
}
