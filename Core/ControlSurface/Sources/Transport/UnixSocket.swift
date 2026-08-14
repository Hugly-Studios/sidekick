import Darwin
import Foundation

enum UnixSocket {
    /// Ceiling for an incoming frame. Requests are a handful of fields, so a
    /// larger announced size is either a bug or an attempt to exhaust memory.
    static let maxFrameSize = 1 << 20

    static func listen(at url: URL) throws -> Int32 {
        try ControlPaths.validatePath(url)
        try ControlPaths.prepareDirectory(for: url)

        unlink(url.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ControlTransportError.socketFailed("socket(): \(errnoMessage)")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        try writePath(url.path, into: &address)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(fd)
            throw ControlTransportError.socketFailed("bind(): \(errnoMessage)")
        }

        chmod(url.path, 0o600)

        guard Darwin.listen(fd, 4) == 0 else {
            close(fd)
            throw ControlTransportError.socketFailed("listen(): \(errnoMessage)")
        }

        return fd
    }

    static func accept(_ listenFD: Int32) throws -> Int32 {
        let client = Darwin.accept(listenFD, nil, nil)
        guard client >= 0 else {
            throw ControlTransportError.socketFailed("accept(): \(errnoMessage)")
        }
        return client
    }

    static func connect(to url: URL) throws -> Int32 {
        try ControlPaths.validatePath(url)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ControlTransportError.socketFailed("socket(): \(errnoMessage)")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        try writePath(url.path, into: &address)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            close(fd)
            throw ControlTransportError.socketFailed("connect(): \(errnoMessage)")
        }

        return fd
    }

    static func send(_ data: Data, on fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < data.count {
                let result = Darwin.send(
                    fd,
                    buffer.baseAddress?.advanced(by: sent),
                    data.count - sent,
                    0
                )
                if result < 0 {
                    throw ControlTransportError.socketFailed("send(): \(errnoMessage)")
                }
                sent += result
            }
        }
    }

    static func receiveFrame(on fd: Int32) throws -> Data {
        let header = try receive(on: fd, count: 4)
        let size = Int(UInt32(bigEndian: header.withUnsafeBytes { $0.load(as: UInt32.self) }))

        guard size <= maxFrameSize else {
            throw ControlTransportError.frameTooLarge(size)
        }

        let body = try receive(on: fd, count: size)
        var frame = header
        frame.append(body)
        return frame
    }

    private static func receive(on fd: Int32, count: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: min(count, 4096))

        while data.count < count {
            let want = min(buffer.count, count - data.count)
            let result = Darwin.recv(fd, &buffer, want, 0)
            if result == 0 {
                throw ControlTransportError.socketFailed("peer closed")
            }
            if result < 0 {
                throw ControlTransportError.socketFailed("recv(): \(errnoMessage)")
            }
            data.append(contentsOf: buffer.prefix(result))
        }

        return data
    }

    private static func writePath(_ path: String, into address: inout sockaddr_un) throws {
        try ControlPaths.validatePath(URL(fileURLWithPath: path))
        let bytes = Array(path.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: bytes)
        }
    }

    private static var errnoMessage: String {
        String(cString: strerror(errno))
    }
}
