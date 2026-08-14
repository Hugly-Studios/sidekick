import Darwin
import Foundation
import Testing

@testable import ControlSurface

struct ControlClientTests {
    /// Short paths on purpose: a temp directory plus a socket name has to stay
    /// under the 104 byte `sun_path` limit.
    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/sk-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func keepsTheSocketWhenNoPidIsRecordedYet() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketURL = directory.appending(path: "cli.sock")
        let pidURL = directory.appending(path: "cli.pid")
        let listener = try UnixSocket.listen(at: socketURL)
        defer { close(listener) }

        #expect(!ControlClient.isAppRunning(socketURL: socketURL, pidURL: pidURL))
        #expect(FileManager.default.fileExists(atPath: socketURL.path))
    }

    @Test func removesTheSocketLeftByADeadProcess() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketURL = directory.appending(path: "cli.sock")
        let pidURL = directory.appending(path: "cli.pid")
        let listener = try UnixSocket.listen(at: socketURL)
        defer { close(listener) }
        // Past any pid the kernel hands out, so it cannot belong to anything.
        try "99999999".write(to: pidURL, atomically: true, encoding: .utf8)

        #expect(!ControlClient.isAppRunning(socketURL: socketURL, pidURL: pidURL))
        #expect(!FileManager.default.fileExists(atPath: socketURL.path))
    }

    @Test func acceptsASocketOwnedByALiveProcess() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketURL = directory.appending(path: "cli.sock")
        let pidURL = directory.appending(path: "cli.pid")
        let listener = try UnixSocket.listen(at: socketURL)
        defer { close(listener) }
        try String(ProcessInfo.processInfo.processIdentifier)
            .write(to: pidURL, atomically: true, encoding: .utf8)

        #expect(ControlClient.isAppRunning(socketURL: socketURL, pidURL: pidURL))
    }

    @MainActor
    @Test func serverRefusesToTakeOverFromALiveOwner() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketURL = directory.appending(path: "cli.sock")
        let pidURL = directory.appending(path: "cli.pid")
        // launchd: always alive, never this process.
        try "1".write(to: pidURL, atomically: true, encoding: .utf8)

        let server = ControlServer(
            handler: FakeHandler(),
            socketURL: socketURL,
            pidURL: pidURL
        )

        #expect(throws: ControlTransportError.self) {
            try server.start()
        }
        #expect(!FileManager.default.fileExists(atPath: socketURL.path))
    }
}
