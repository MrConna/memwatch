import Foundation

@MainActor
public final class MemoryMonitor: ObservableObject {
    @Published public private(set) var snapshot: MemorySnapshot?
    @Published public private(set) var analysis = MemoryAnalysis(level: .unknown, reasons: [], shouldNotify: false, event: nil)
    @Published public private(set) var isRunning = false

    private let sampler: MemorySampler
    private let analyzer: MemoryAnalyzer
    private let settingsStore: SettingsStore
    private let eventStore: EventStore
    private let notificationService: NotificationService
    private var timer: Timer?

    public init(
        sampler: MemorySampler = MemorySampler(),
        analyzer: MemoryAnalyzer = MemoryAnalyzer(),
        settingsStore: SettingsStore = SettingsStore(),
        eventStore: EventStore = EventStore(),
        notificationService: NotificationService = NotificationService()
    ) {
        self.sampler = sampler
        self.analyzer = analyzer
        self.settingsStore = settingsStore
        self.eventStore = eventStore
        self.notificationService = notificationService
    }

    public var events: [MemoryEvent] {
        eventStore.events
    }

    public var settings: MemorySettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        notificationService.requestPermissionIfNeeded()
        sampleNow()
        scheduleTimer()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    public func sampleNow() {
        let currentSettings = settingsStore.settings
        do {
            let currentSnapshot = try sampler.sample(settings: currentSettings)
            let currentAnalysis = analyzer.analyze(snapshot: currentSnapshot, settings: currentSettings)
            snapshot = currentSnapshot
            analysis = currentAnalysis
            if let event = currentAnalysis.event {
                eventStore.add(event)
                notificationService.send(event: event)
            }
        } catch {
            snapshot = MemorySnapshot(
                totalBytes: 0,
                usedBytes: 0,
                availableBytes: 0,
                swapUsedBytes: 0,
                pressure: .unknown,
                topProcesses: [],
                errorMessage: error.localizedDescription
            )
            analysis = MemoryAnalysis(level: .unknown, reasons: [], shouldNotify: false, event: nil)
        }
    }

    public func updateSettings(_ mutate: (inout MemorySettings) -> Void) {
        var next = settingsStore.settings
        mutate(&next)
        settingsStore.settings = next
        if isRunning {
            scheduleTimer()
        }
    }

    public func clearEvents() {
        eventStore.clear()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = max(5, settingsStore.settings.samplingIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let monitor = self else { return }
            Task { @MainActor in
                monitor.sampleNow()
            }
        }
    }
}
