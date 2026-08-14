import Darwin
import Foundation

public enum ControlClient {
    public static func send(
        _ operation: ControlRequest.Operation,
        socketURL: URL = ControlPaths.socketURL,
        pidURL: URL = ControlPaths.pidURL,
        timeout: TimeInterval = 30
    ) throws -> ControlResponse {
        try ensureRunning(socketURL: socketURL, pidURL: pidURL)

        let fd = try UnixSocket.connect(to: socketURL)
        defer { close(fd) }

        try PeerAuthenticator.checkUID(fd)

        let request = ControlRequest(operation: operation)
        try UnixSocket.send(try ControlCodec.encode(request), on: fd)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var fds = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&fds, 1, 100)
            if ready > 0 {
                let frame = try UnixSocket.receiveFrame(on: fd)
                return try ControlCodec.decode(frame, as: ControlResponse.self)
            }
        }

        throw ControlTransportError.timeout
    }

    public static func isAppRunning(
        socketURL: URL = ControlPaths.socketURL,
        pidURL: URL = ControlPaths.pidURL
    ) -> Bool {
        (try? ensureRunning(socketURL: socketURL, pidURL: pidURL)) != nil
    }

    private static func ensureRunning(socketURL: URL, pidURL: URL) throws {
        guard FileManager.default.fileExists(atPath: socketURL.path) else {
            throw ControlTransportError.notRunning
        }

        switch ControlPaths.pidState(at: pidURL) {
        case .live:
            return
        case .missing:
            // Nobody claims this socket, so nobody may declare it garbage
            // either: deleting it would cut off a server that is still there.
            throw ControlTransportError.notRunning
        case .dead:
            try? FileManager.default.removeItem(at: socketURL)
            try? FileManager.default.removeItem(at: pidURL)
            throw ControlTransportError.staleSocket
        }
    }
}
