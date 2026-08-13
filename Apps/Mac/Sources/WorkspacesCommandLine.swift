import Foundation

/// One-shot desktop layout commands.
///
/// The work is done by the running app: this process only asks for it, because a
/// binary started from a terminal inherits the terminal's (missing) permissions.
@MainActor
enum WorkspacesCommandLine {
    /// Returns true when an argument was handled and the app must not start.
    static func run(arguments: [String]) -> Bool {
        guard let request = parse(arguments) else { return false }

        guard RemoteControl.isAppRunning else {
            print("Sidekick не запущен — откройте приложение и повторите")
            return true
        }

        guard let reply = RemoteControl.send(request.action, argument: request.argument) else {
            print("приложение не ответило")
            return true
        }

        print(reply)
        return true
    }

    private static func parse(_ arguments: [String]) -> (
        action: RemoteControl.Action, argument: String
    )? {
        if arguments.contains("--status") { return (.status, "verbose") }
        if arguments.contains("--snapshots") { return (.list, "") }

        if let name = value(after: "--capture", in: arguments) { return (.capture, name) }
        if let name = value(after: "--restore", in: arguments) { return (.restore, name) }

        return nil
    }

    /// The flag may come with or without a value: `--capture` or `--capture работа`.
    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }

        let next = arguments.index(after: index)
        guard next < arguments.endIndex, !arguments[next].hasPrefix("--") else { return "" }

        return arguments[next]
    }
}
