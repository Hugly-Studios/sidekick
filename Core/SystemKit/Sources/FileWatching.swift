import Foundation

public struct FileWatchEvent: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

/// Directory changes without a feature talking to Dispatch or FSEvents itself.
public protocol FileWatching: Sendable {
    func events(at url: URL) -> AsyncStream<FileWatchEvent>
}

public struct LiveFileWatcher: FileWatching {
    public init() {}

    public func events(at url: URL) -> AsyncStream<FileWatchEvent> {
        AsyncStream { continuation in
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                continuation.finish()
                return
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete],
                queue: DispatchQueue.global(qos: .utility)
            )

            source.setEventHandler {
                continuation.yield(FileWatchEvent(url: url))
            }

            source.setCancelHandler {
                close(descriptor)
            }

            continuation.onTermination = { _ in
                source.cancel()
            }

            source.resume()
        }
    }
}
