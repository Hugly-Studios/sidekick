import AppKit
import Foundation

/// Lets a short-lived process ask the running Sidekick to do something.
///
/// Required, not convenient: macOS attributes permissions to the process that
/// started a binary, so a copy of Sidekick launched from a terminal is judged as
/// the terminal and has no Accessibility access, no matter what the app itself was
/// granted. Only the instance launched by the system can read and move windows.
@MainActor
enum RemoteControl {
    enum Action: String {
        case status
        case list
        case capture
        case restore
    }

    static var isAppRunning: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }

        let currentPID = ProcessInfo.processInfo.processIdentifier

        return
            NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != currentPID }
    }

    // MARK: - App side

    static func observe(_ handler: @escaping @MainActor (Action, String) async -> String) {
        DistributedNotificationCenter.default().addObserver(
            forName: requestName,
            object: nil,
            queue: .main
        ) { notification in
            guard let raw = notification.userInfo?[actionKey] as? String,
                let action = Action(rawValue: raw)
            else { return }

            let argument = notification.userInfo?[argumentKey] as? String ?? ""

            MainActor.assumeIsolated {
                Task {
                    let reply = await handler(action, argument)
                    respond(reply)
                }
            }
        }
    }

    private static func respond(_ reply: String) {
        DistributedNotificationCenter.default().postNotificationName(
            responseName,
            object: nil,
            userInfo: [replyKey: reply],
            deliverImmediately: true
        )
    }

    // MARK: - Client side

    /// Posts a request and spins the run loop until the app answers.
    static func send(_ action: Action, argument: String = "", timeout: TimeInterval = 300)
        -> String?
    {
        var reply: String?

        let observer = DistributedNotificationCenter.default().addObserver(
            forName: responseName,
            object: nil,
            queue: .main
        ) { notification in
            reply = notification.userInfo?[replyKey] as? String ?? ""
        }

        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        DistributedNotificationCenter.default().postNotificationName(
            requestName,
            object: nil,
            userInfo: [actionKey: action.rawValue, argumentKey: argument],
            deliverImmediately: true
        )

        let deadline = Date().addingTimeInterval(timeout)

        while reply == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return reply
    }

    private static let requestName = Notification.Name("com.hugly.sidekick.remote.request")
    private static let responseName = Notification.Name("com.hugly.sidekick.remote.response")
    private static let actionKey = "action"
    private static let argumentKey = "argument"
    private static let replyKey = "reply"
}
