import Darwin
import Foundation

public enum ControlPaths {
    public static let directoryName = "com.hugly.sidekick"
    public static let socketName = "cli.sock"
    public static let pidName = "cli.pid"
    public static let sunPathLimit = 104

    public static var supportDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: directoryName, directoryHint: .isDirectory)
    }

    public static var socketURL: URL {
        supportDirectory.appending(path: socketName)
    }

    public static var pidURL: URL {
        supportDirectory.appending(path: pidName)
    }

    public static func validatePath(_ url: URL) throws {
        let path = url.path
        // sockaddr_un.sun_path is 104 bytes including the trailing NUL.
        if path.utf8.count + 1 > sunPathLimit {
            throw ControlTransportError.pathTooLong(path)
        }
    }

    /// Creates the directory holding the socket and the pid file, readable by
    /// this user only.
    static func prepareDirectory(for url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard directory.lastPathComponent == directoryName else { return }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    /// Whether the recorded pid still belongs to a running process. Telling
    /// "no pid yet" apart from "pid of a corpse" is what keeps a starting server
    /// from being mistaken for a crashed one.
    static func pidState(at url: URL) -> PidState {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
            let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return .missing
        }

        // EPERM means the pid is taken by a process this user may not signal,
        // which still makes it alive.
        if kill(pid, 0) == 0 || errno == EPERM {
            return .live(pid)
        }

        return .dead(pid)
    }

    enum PidState {
        case missing
        case live(Int32)
        case dead(Int32)
    }
}

public enum ControlTransportError: Error, LocalizedError {
    case pathTooLong(String)
    case socketFailed(String)
    case notRunning
    case staleSocket
    case alreadyRunning(pid: Int32)
    case frameTooLarge(Int)
    case timeout
    case peerRejected(String)

    public var errorDescription: String? {
        switch self {
        case .pathTooLong(let path):
            "socket path exceeds 104 bytes: \(path)"
        case .socketFailed(let reason):
            reason
        case .notRunning:
            "Sidekick не запущен — откройте приложение и повторите"
        case .staleSocket:
            "сокет остался от упавшего процесса"
        case .alreadyRunning(let pid):
            "control socket already served by pid \(pid)"
        case .frameTooLarge(let size):
            "frame of \(size) bytes exceeds the limit"
        case .timeout:
            "приложение не ответило"
        case .peerRejected(let reason):
            reason
        }
    }
}
