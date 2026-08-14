import Foundation

/// Accepts CLI connections on a unix socket and routes them to a handler.
@MainActor
public final class ControlServer {
    private let handler: any ControlHandling
    private let socketURL: URL
    private let pidURL: URL
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    public init(
        handler: any ControlHandling,
        socketURL: URL = ControlPaths.socketURL,
        pidURL: URL = ControlPaths.pidURL
    ) {
        self.handler = handler
        self.socketURL = socketURL
        self.pidURL = pidURL
    }

    public func start() throws {
        if case .live(let pid) = ControlPaths.pidState(at: pidURL),
            pid != ProcessInfo.processInfo.processIdentifier
        {
            throw ControlTransportError.alreadyRunning(pid: pid)
        }

        // The pid lands before the socket so a client that finds a socket always
        // finds an owner for it, and never mistakes a start for a crash.
        try writePID()
        listenFD = try UnixSocket.listen(at: socketURL)

        let fd = listenFD
        // The handler captures `self` and is therefore MainActor-isolated.
        // A global queue trips Swift's executor check and kills the process
        // (EXC_BREAKPOINT in `_swift_task_checkIsolatedSwift`). Accept is
        // ready when the source fires; the blocking work stays off-main
        // inside `serve`.
        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            do {
                let client = try UnixSocket.accept(fd)
                Task { await self?.serve(client) }
            } catch {
                return
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        acceptSource = source
        source.resume()
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        try? FileManager.default.removeItem(at: socketURL)
        try? FileManager.default.removeItem(at: pidURL)
    }

    /// Only routing runs on the main actor. Reading and writing a socket blocks
    /// for as long as the peer wants it to, and the menu bar must not wait.
    private func serve(_ client: Int32) async {
        defer { close(client) }

        do {
            try await Self.authenticate(client)
        } catch {
            // An unauthenticated peer learns nothing, not even why.
            return
        }

        let response: ControlResponse
        do {
            let frame = try await Self.receiveFrame(on: client)
            let request = try ControlCodec.decode(frame, as: ControlRequest.self)
            response = await ControlRouter.route(request, using: handler)
        } catch {
            response = .failure(id: UUID(), error: error.localizedDescription)
        }

        try? await Self.send(response, on: client)
    }

    @concurrent
    private nonisolated static func authenticate(_ client: Int32) async throws {
        try PeerAuthenticator.accept(client)
    }

    @concurrent
    private nonisolated static func receiveFrame(on client: Int32) async throws -> Data {
        try UnixSocket.receiveFrame(on: client)
    }

    @concurrent
    private nonisolated static func send(
        _ response: ControlResponse,
        on client: Int32
    ) async throws {
        try UnixSocket.send(try ControlCodec.encode(response), on: client)
    }

    private func writePID() throws {
        try ControlPaths.prepareDirectory(for: pidURL)
        try String(ProcessInfo.processInfo.processIdentifier)
            .write(to: pidURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pidURL.path
        )
    }
}
