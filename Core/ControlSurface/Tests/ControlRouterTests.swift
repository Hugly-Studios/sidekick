import Foundation
import Testing

@testable import ControlSurface

@MainActor
final class FakeHandler: ControlHandling {
    var enabled: [String: Bool] = ["workspaces": false]
    var lastRun: (id: String, argument: String?)?
    var quitCalled = false

    func status() async -> StatusPayload {
        StatusPayload(
            version: "0.1.0",
            build: "1",
            path: "/tmp/Sidekick.app",
            pid: 1,
            features: listFeatures()
        )
    }

    func listFeatures() -> [FeatureInfo] {
        [
            FeatureInfo(
                id: "workspaces",
                title: "Рабочие столы",
                enabled: enabled["workspaces"] ?? false,
                failure: nil
            )
        ]
    }

    func setFeature(id: String, enabled: Bool) async throws -> FeatureInfo {
        guard id == "workspaces" else { throw ControlHandlerError.featureNotFound(id) }
        self.enabled[id] = enabled
        return FeatureInfo(id: id, title: "Рабочие столы", enabled: enabled, failure: nil)
    }

    func listCommands() -> [CommandInfo] {
        [CommandInfo(id: "workspaces.capture", title: "Сохранить", owner: "workspaces")]
    }

    func run(commandID: String, argument: String?) async throws -> String {
        lastRun = (commandID, argument)
        return argument.map { "ran \($0)" } ?? "ok"
    }

    func settingsGet(_ key: String) -> String? {
        key == "features.workspaces.restoreOnLogin" ? "false" : nil
    }

    func settingsSet(_ key: String, _ value: String) {
        _ = (key, value)
    }

    func logs(sinceSeconds: Double, level: String?) throws -> [LogRecord] {
        _ = (sinceSeconds, level)
        return []
    }

    func doctor() async -> DoctorPayload {
        DoctorPayload(
            bundleID: "com.hugly.sidekick",
            version: "0.1.0",
            build: "1",
            path: "/tmp/Sidekick.app",
            teamID: nil,
            signingKind: "ad-hoc",
            loginItem: "not registered",
            shortcut: nil,
            menuBarIcon: "unknown",
            permissions: [],
            warnings: [],
            running: true
        )
    }

    func quit() {
        quitCalled = true
    }
}

@MainActor
struct ControlRouterTests {
    @Test func enablesAFeature() async {
        let handler = FakeHandler()
        let request = ControlRequest(operation: .featureEnable(id: "workspaces"))
        let response = await ControlRouter.route(request, using: handler)

        #expect(response.ok)
        #expect(handler.enabled["workspaces"] == true)
    }

    @Test func reportsUnknownFeature() async {
        let handler = FakeHandler()
        let request = ControlRequest(operation: .featureEnable(id: "nope"))
        let response = await ControlRouter.route(request, using: handler)

        #expect(!response.ok)
        #expect(response.error?.contains("nope") == true)
    }

    @Test func runsACommandWithArgument() async {
        let handler = FakeHandler()
        let request = ControlRequest(operation: .run(id: "workspaces.capture", argument: "дом"))
        let response = await ControlRouter.route(request, using: handler)

        #expect(response.ok)
        #expect(handler.lastRun?.id == "workspaces.capture")
        #expect(handler.lastRun?.argument == "дом")
    }

    @Test func quitSetsTheFlag() async {
        let handler = FakeHandler()
        let response = await ControlRouter.route(ControlRequest(operation: .quit), using: handler)

        #expect(response.ok)
        #expect(handler.quitCalled)
    }
}
