import ControlSurface
import Foundation

/// One-shot CLI. Talks to the running app over the control socket.
@MainActor
enum ControlCommandLine {
    /// Returns true when an argument was handled and the app must not start.
    ///
    /// Only a bare launch opens the app. A misspelled verb has to fail loudly:
    /// silently starting the GUI instead would read as success to a caller that
    /// only checks the exit code.
    static func run(arguments: [String]) -> Bool {
        let json = arguments.contains("--json")
        let words = Array(arguments.dropFirst().filter { $0 != "--json" })

        guard !words.isEmpty else { return false }

        guard let operation = parse(words) else {
            fputs("неизвестная команда: \(words.joined(separator: " "))\n", stderr)
            fputs("\(usage)\n", stderr)
            exit(1)
        }

        return handle(operation, json: json)
    }

    private static let usage = """
        команды: status | features list|enable <id>|disable <id> | commands \
        | run <command.id> [--arg …] | settings get|set <key> [value] \
        | logs [--since 1h] [--level error] | doctor | quit
        """

    private static func handle(_ operation: ControlRequest.Operation, json: Bool) -> Bool {
        if case .logs(let since, let level) = operation {
            do {
                let records = try LogReader.fetch(since: since, level: level)
                printOutput(
                    ControlResponse.success(id: UUID(), payload: .logs(records)),
                    json: json
                )
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return true
        }

        if operation.isDoctor, !ControlClient.isAppRunning() {
            printOfflineDoctor(json: json)
            return true
        }

        do {
            let response = try ControlClient.send(operation)
            printOutput(withMenuBarIcon(response), json: json)
            if !response.ok {
                exit(1)
            }
        } catch let error as ControlTransportError {
            if case .notRunning = error, operation.isDoctor {
                printOfflineDoctor(json: json)
                return true
            }

            fputs("\(error.localizedDescription)\n", stderr)
            exit(error.exitCode)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }

        return true
    }

    private static func printOfflineDoctor(json: Bool) {
        printOutput(
            withMenuBarIcon(.success(id: UUID(), payload: .doctor(Doctor.offline()))),
            json: json
        )
    }

    /// The running app cannot measure its own icon's placement, so the report
    /// arrives without it and this process fills it in.
    private static func withMenuBarIcon(_ response: ControlResponse) -> ControlResponse {
        guard let existing = response.payload,
            case .doctor(let payload) = existing
        else {
            return response
        }

        return ControlResponse(
            id: response.id,
            ok: response.ok,
            error: response.error,
            payload: .doctor(MenuBarIconProbe.annotate(payload))
        )
    }

    private static func parse(_ words: [String]) -> ControlRequest.Operation? {
        guard let first = words.first else { return nil }
        let rest = Array(words.dropFirst())

        switch first {
        case "status":
            return .status
        case "features":
            return parseFeatures(rest)
        case "commands":
            return .commands
        case "run":
            return parseRun(rest)
        case "settings":
            return parseSettings(rest)
        case "logs":
            return parseLogs(rest)
        case "doctor":
            return .doctor
        case "quit":
            return .quit
        default:
            return nil
        }
    }

    private static func parseFeatures(_ args: [String]) -> ControlRequest.Operation? {
        guard let action = args.first else { return .featuresList }

        switch action {
        case "list":
            return .featuresList
        case "enable":
            guard args.count >= 2 else { return nil }
            return .featureEnable(id: args[1])
        case "disable":
            guard args.count >= 2 else { return nil }
            return .featureDisable(id: args[1])
        default:
            return nil
        }
    }

    private static func parseRun(_ args: [String]) -> ControlRequest.Operation? {
        guard let id = args.first else { return nil }
        let argument = value(after: "--arg", in: args)
        return .run(id: id, argument: argument)
    }

    private static func parseSettings(_ args: [String]) -> ControlRequest.Operation? {
        guard let action = args.first, args.count >= 2 else { return nil }

        switch action {
        case "get":
            return .settingsGet(key: args[1])
        case "set":
            guard args.count >= 3 else { return nil }
            return .settingsSet(key: args[1], value: args[2])
        default:
            return nil
        }
    }

    private static func parseLogs(_ args: [String]) -> ControlRequest.Operation {
        let raw = value(after: "--since", in: args) ?? "1h"
        let since = parseDuration(raw) ?? 3600
        let level = value(after: "--level", in: args)
        return .logs(sinceSeconds: since, level: level)
    }

    private static func parseDuration(_ raw: String) -> Double? {
        if raw.hasSuffix("m"), let minutes = Double(raw.dropLast()) {
            return minutes * 60
        }
        if raw.hasSuffix("s"), let seconds = Double(raw.dropLast()) {
            return seconds
        }
        if raw.hasSuffix("h"), let hours = Double(raw.dropLast()) {
            return hours * 3600
        }
        return Double(raw)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }

        let next = arguments.index(after: index)
        guard next < arguments.endIndex, !arguments[next].hasPrefix("--") else { return nil }

        return arguments[next]
    }

    private static func printOutput(_ response: ControlResponse, json: Bool) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard json, let data = try? encoder.encode(response),
            let text = String(data: data, encoding: .utf8)
        else {
            if let error = response.error {
                print(error)
            } else if let payload = response.payload {
                print(payload.plainText)
            }
            return
        }

        print(text)
    }
}

extension ControlRequest.Operation {
    fileprivate var isDoctor: Bool {
        if case .doctor = self { return true }
        return false
    }
}

extension ControlTransportError {
    fileprivate var exitCode: Int32 {
        switch self {
        case .notRunning, .staleSocket:
            2
        default:
            1
        }
    }
}

extension ControlResponse.Payload {
    fileprivate var plainText: String {
        switch self {
        case .status(let status):
            "\(status.version) (\(status.build)) — \(status.features.count) modules"
        case .features(let features):
            features.map { "\($0.enabled ? "*" : " ") \($0.id) \($0.failure ?? "")" }
                .joined(separator: "\n")
        case .feature(let feature):
            "\(feature.id) enabled=\(feature.enabled) \(feature.failure ?? "")"
        case .commands(let commands):
            commands.map { "\($0.owner) \($0.id)" }.joined(separator: "\n")
        case .run(let message):
            message
        case .setting(let key, let value):
            "\(key)=\(value ?? "")"
        case .logs(let records):
            records.map { "\($0.level) \($0.category) \($0.message)" }.joined(separator: "\n")
        case .doctor(let doctor):
            "\(doctor.bundleID) \(doctor.version) (\(doctor.build)) \(doctor.signingKind)"
        case .quit:
            "ok"
        }
    }
}
