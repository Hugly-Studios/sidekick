import Foundation
import Testing

@testable import ControlSurface

struct UnixSocketTests {
    @Test func rejectsAPathOverTheSunPathLimit() {
        let long = String(repeating: "a", count: 200)
        let url = URL(fileURLWithPath: "/tmp/\(long).sock")

        #expect(throws: ControlTransportError.self) {
            try ControlPaths.validatePath(url)
        }
    }

    @Test func exchangesAFrameOnATemporarySocket() throws {
        let url = URL(fileURLWithPath: "/tmp/sk-\(ProcessInfo.processInfo.processIdentifier).sock")
        defer { try? FileManager.default.removeItem(at: url) }
        let server = try UnixSocket.listen(at: url)
        defer { close(server) }

        let client = try UnixSocket.connect(to: url)
        defer { close(client) }

        let accepted = try UnixSocket.accept(server)
        defer { close(accepted) }

        try PeerAuthenticator.checkUID(accepted)
        try PeerAuthenticator.checkUID(client)

        let request = ControlRequest(operation: .status)
        try UnixSocket.send(try ControlCodec.encode(request), on: client)
        let frame = try UnixSocket.receiveFrame(on: accepted)
        let decoded = try ControlCodec.decode(frame, as: ControlRequest.self)

        #expect(decoded.operation == .status)
    }

    @Test func requirementCoversDevelopmentAndDeveloperID() {
        let text = PeerAuthenticator.requirementText(teamID: "ABCDE12345")

        #expect(text.contains("1.2.840.113635.100.6.2.1"))
        #expect(text.contains("1.2.840.113635.100.6.1.13"))
        #expect(text.contains("ABCDE12345"))
        #expect(text.contains(" or "))
    }
}
