import Foundation

public final class SettingsStore: ObservableObject {
    @Published public var settings: MemorySettings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "memwatch.settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(MemorySettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = MemorySettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

public final class EventStore: ObservableObject {
    @Published public private(set) var events: [MemoryEvent]

    private let defaults: UserDefaults
    private let key = "memwatch.events.v1"
    private let limit: Int

    public init(defaults: UserDefaults = .standard, limit: Int = 20) {
        self.defaults = defaults
        self.limit = limit
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([MemoryEvent].self, from: data) {
            self.events = decoded
        } else {
            self.events = []
        }
    }

    public func add(_ event: MemoryEvent) {
        events.insert(event, at: 0)
        events = Array(events.prefix(limit))
        save()
    }

    public func clear() {
        events = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: key)
    }
}

