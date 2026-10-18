import Darwin
import Foundation
import OBDCore
import Synchronization

/// POSIX serial line to a USB adapter (`/dev/cu.*`), opened exclusively, raw 8N1.
/// Blocking reads run on a private dispatch queue, never on the Swift concurrency pool.
public final class SerialLink: AdapterLink {
    public let label: String
    private let fd: Int32
    private let queue: DispatchQueue
    private let state = Mutex(State())

    private struct State {
        var closed = false
        var disconnected = false
    }

    /// `_IO('t', 13)`, not imported by Swift because it is a function-like macro.
    static let tiocexcl: UInt = 0x2000_740D

    private init(fd: Int32, label: String) {
        self.fd = fd
        self.label = label
        queue = DispatchQueue(label: "openobd.serial")
    }

    deinit {
        state.withLock { state in
            if !state.closed {
                state.closed = true
                Darwin.close(fd)
            }
        }
    }

    public static func open(path: String, baudRate: Int = 115_200) throws -> SerialLink {
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            throw openError(path: path, code: errno)
        }
        do {
            // TIOCEXCL keeps foreign programs out. macOS does not enforce it on every device type,
            // so an advisory flock additionally serializes our own processes (GUI and CLI).
            guard ioctl(fd, tiocexcl) == 0 else {
                throw openError(path: path, code: errno)
            }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                throw errno == EWOULDBLOCK ? OBDError.portBusy(path) : openError(path: path, code: errno)
            }
            try configure(fd: fd, path: path, baudRate: baudRate)
        } catch {
            Darwin.close(fd)
            throw error
        }
        return SerialLink(fd: fd, label: path)
    }

    private static func openError(path: String, code: Int32) -> OBDError {
        code == EBUSY ? .portBusy(path) : .portOpenFailed(path: path, errno: code)
    }

    private static func configure(fd: Int32, path: String, baudRate: Int) throws {
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            throw OBDError.portOpenFailed(path: path, errno: errno)
        }
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        withUnsafeMutableBytes(of: &options.c_cc) { buffer in
            buffer[Int(VMIN)] = 0
            buffer[Int(VTIME)] = 0
        }
        guard cfsetspeed(&options, speed_t(baudRate)) == 0, tcsetattr(fd, TCSANOW, &options) == 0 else {
            throw OBDError.portOpenFailed(path: path, errno: errno)
        }
        tcflush(fd, TCIOFLUSH)
    }

    public func transact(_ command: String, timeout: Duration) async throws -> LinkReply {
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LinkReply, any Error>) in
                queue.async {
                    do {
                        continuation.resume(returning: try self.blockingTransact(command, timeout: timeout, cancellation: cancellation))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    public func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.state.withLock { state in
                    if !state.closed {
                        state.closed = true
                        Darwin.close(self.fd)
                    }
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Blocking I/O on `queue`

    private func blockingTransact(_ command: String, timeout: Duration, cancellation: CancellationFlag) throws -> LinkReply {
        let usable = state.withLock { !$0.closed && !$0.disconnected }
        guard usable else { throw OBDError.disconnected }
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: timeout)

        drainInput()
        try writeAll(Array((command + "\r").utf8), deadline: deadline, cancellation: cancellation)

        var received: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 512)
        while true {
            if cancellation.isCancelled { throw OBDError.cancelled }
            let now = clock.now
            guard now < deadline else {
                throw OBDError.timeout("keine vollständige Antwort auf \(command) innerhalb von \(timeout.wholeMilliseconds) ms")
            }
            let wait = Int32(clamping: min(50, max(1, (deadline - now).wholeMilliseconds)))
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, wait)
            if ready < 0 {
                if errno == EINTR { continue }
                throw OBDError.io("poll: \(String(cString: strerror(errno)))")
            }
            if ready == 0 { continue }
            let count = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                markDisconnected()
                throw OBDError.disconnected
            }
            if count == 0 {
                markDisconnected()
                throw OBDError.disconnected
            }
            received.append(contentsOf: chunk[0..<count])
            if let prompt = received.firstIndex(of: UInt8(ascii: ">")) {
                return LinkReply(text: String(decoding: received[..<prompt], as: UTF8.self), elapsed: clock.now - start)
            }
        }
    }

    private func writeAll(_ bytes: [UInt8], deadline: ContinuousClock.Instant, cancellation: CancellationFlag) throws {
        var offset = 0
        while offset < bytes.count {
            if cancellation.isCancelled { throw OBDError.cancelled }
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written > 0 {
                offset += written
                continue
            }
            if written < 0, errno == EAGAIN || errno == EINTR {
                guard ContinuousClock.now < deadline else {
                    throw OBDError.timeout("Schreiben zum Adapter blockiert")
                }
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                _ = poll(&descriptor, 1, 20)
                continue
            }
            markDisconnected()
            throw OBDError.disconnected
        }
    }

    private func drainInput() {
        var scratch = [UInt8](repeating: 0, count: 256)
        while scratch.withUnsafeMutableBytes({ Darwin.read(fd, $0.baseAddress, $0.count) }) > 0 {}
    }

    private func markDisconnected() {
        state.withLock { $0.disconnected = true }
    }
}

/// Cancellation signal shared between a Swift task and the serial queue.
final class CancellationFlag: Sendable {
    private let flag = Mutex(false)

    var isCancelled: Bool { flag.withLock { $0 } }

    func cancel() {
        flag.withLock { $0 = true }
    }
}
