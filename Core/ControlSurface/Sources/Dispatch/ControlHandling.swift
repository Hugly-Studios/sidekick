import Foundation

/// App-side work the socket server asks for. Lives behind a protocol so the
/// router and the transport can be tested without AppKit.
@MainActor
public protocol ControlHandling: AnyObject {
    func status() async -> StatusPayload
    func listFeatures() -> [FeatureInfo]
    func setFeature(id: String, enabled: Bool) async throws -> FeatureInfo
    func listCommands() -> [CommandInfo]
    func run(commandID: String, argument: String?) async throws -> String
    func settingsGet(_ key: String) -> String?
    func settingsSet(_ key: String, _ value: String)
    func logs(sinceSeconds: Double, level: String?) throws -> [LogRecord]
    func doctor() async -> DoctorPayload
    func quit()
}

@MainActor
public enum ControlRouter {
    public static func route(_ request: ControlRequest, using handler: any ControlHandling) async
        -> ControlResponse
    {
        do {
            let payload = try await perform(request.operation, using: handler)
            return .success(id: request.id, payload: payload)
        } catch {
            return .failure(id: request.id, error: error.localizedDescription)
        }
    }

    private static func perform(
        _ operation: ControlRequest.Operation,
        using handler: any ControlHandling
    ) async throws -> ControlResponse.Payload {
        switch operation {
        case .status:
            return .status(await handler.status())
        case .featuresList:
            return .features(handler.listFeatures())
        case .featureEnable(let id):
            return .feature(try await handler.setFeature(id: id, enabled: true))
        case .featureDisable(let id):
            return .feature(try await handler.setFeature(id: id, enabled: false))
        case .commands:
            return .commands(handler.listCommands())
        case .run(let id, let argument):
            let message = try await handler.run(commandID: id, argument: argument)
            return .run(message: message.isEmpty ? "ok" : message)
        case .settingsGet(let key):
            return .setting(key: key, value: handler.settingsGet(key))
        case .settingsSet(let key, let value):
            handler.settingsSet(key, value)
            return .setting(key: key, value: value)
        case .logs(let since, let level):
            return .logs(try handler.logs(sinceSeconds: since, level: level))
        case .doctor:
            return .doctor(await handler.doctor())
        case .quit:
            handler.quit()
            return .quit
        }
    }
}

public enum ControlHandlerError: Error, LocalizedError {
    case featureNotFound(String)

    nonisolated public var errorDescription: String? {
        switch self {
        case .featureNotFound(let id):
            "модуль не найден: \(id)"
        }
    }
}
