import Darwin
import Foundation
import Synchronization

/// Unix domain sockets for the bridge. Local only, owner only.
enum BridgeSocket {
    struct Failure: Error {
        let call: String
        let errno: Int32

        var text: String { "\(call): \(String(cString: strerror(errno)))" }
    }

    enum Accepted {
        case client(Int32)
        case timeout
        case failed
    }

    static func connect(to path: String) throws -> Int32 {
        var address = try makeAddress(path)
        let fd = try makeSocket()
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(fd)
            throw Failure(call: "connect", errno: code)
        }
        return fd
    }

    /// Replaces a stale socket file, refuses when another server still answers.
    static func listen(at path: String) throws -> Int32 {
        if FileManager.default.fileExists(atPath: path) {
            if let fd = try? connect(to: path) {
                Darwin.close(fd)
                throw BridgeError.alreadyRunning(path: path)
            }
            unlink(path)
        }
        let folder = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var address = try makeAddress(path)
        let fd = try makeSocket()
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(fd)
            throw BridgeError.socket(Failure(call: "bind", errno: code).text)
        }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 8) == 0 else {
            let code = errno
            Darwin.close(fd)
            unlink(path)
            throw BridgeError.socket(Failure(call: "listen", errno: code).text)
        }
        return fd
    }

    /// Waits up to `timeoutMilliseconds` for a client, so the accept loop can notice a stop.
    static func accept(_ listener: Int32, timeoutMilliseconds: Int32) -> Accepted {
        var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, timeoutMilliseconds)
        if ready == 0 { return .timeout }
        guard ready > 0 else { return errno == EINTR ? .timeout : .failed }
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return errno == EINTR || errno == ECONNABORTED ? .timeout : .failed }
        configure(fd)
        return .client(fd)
    }

    static func peerIsCurrentUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    private static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.socket(Failure(call: "socket", errno: errno).text) }
        configure(fd)
        return fd
    }

    /// No SIGPIPE when the other side is gone, no inheritance by child processes.
    private static func configure(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    private static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw BridgeError.socket("Pfad zu lang (\(bytes.count) Bytes): \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
}

/// A connected socket that reads lines on its own thread and writes whole lines under a lock.
/// The reader owns the descriptor and closes it when the stream ends, so no write ever hits a closed descriptor.
final class LineChannel: Sendable {
    let incoming: AsyncStream<String>
    private let fd: Int32
    /// True once the descriptor is closed. Writers hold the lock for the whole line.
    private let closed = Mutex(false)
    static let maximumLineBytes = 64 << 20

    init(fd: Int32) {
        self.fd = fd
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        incoming = stream
        let thread = Thread { [self] in
            readLines(into: continuation)
        }
        thread.name = "openobd.bridge.reader"
        thread.start()
    }

    func send(_ line: String) throws {
        try closed.withLock { isClosed in
            guard !isClosed else { throw BridgeError.disconnected }
            let bytes = Array(line.utf8) + [0x0A]
            var offset = 0
            while offset < bytes.count {
                let written = bytes.withUnsafeBytes { buffer in
                    Darwin.write(fd, buffer.baseAddress! + offset, bytes.count - offset)
                }
                if written < 0 {
                    if errno == EINTR { continue }
                    throw BridgeError.disconnected
                }
                offset += written
            }
        }
    }

    /// Wakes the reader. The reader then closes the descriptor.
    func close() {
        closed.withLock { isClosed in
            if !isClosed { _ = shutdown(fd, SHUT_RDWR) }
        }
    }

    private func readLines(into continuation: AsyncStream<String>.Continuation) {
        var pending: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        reading: while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            pending.append(contentsOf: buffer[0..<count])
            var start = 0
            while let newline = pending[start...].firstIndex(of: 0x0A) {
                continuation.yield(String(decoding: pending[start..<newline], as: UTF8.self))
                start = newline + 1
            }
            pending.removeFirst(start)
            if pending.count > Self.maximumLineBytes { break reading }
        }
        closed.withLock { isClosed in
            isClosed = true
            Darwin.close(fd)
        }
        continuation.finish()
    }
}
