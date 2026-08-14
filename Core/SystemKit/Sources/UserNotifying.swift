import Foundation
import UserNotifications

public protocol UserNotifying: Sendable {
    func notify(title: String, body: String) async
}

public struct LiveUserNotifier: UserNotifying {
    public init() {}

    public func notify(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
