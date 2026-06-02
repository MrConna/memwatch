import Foundation
import UserNotifications

public final class NotificationService {
    public init() {}

    public func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func send(event: MemoryEvent) {
        let content = UNMutableNotificationContent()
        content.title = "MemWatch: memory \(event.level.rawValue)"
        content.body = event.message
        content.sound = .default

        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

