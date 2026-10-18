import Foundation
import Synchronization

/// Where command output goes. Standard output by default, a buffer in tests.
public struct OutputSink: Sendable {
    public let out: @Sendable (String) -> Void
    public let err: @Sendable (String) -> Void

    public init(out: @escaping @Sendable (String) -> Void, err: @escaping @Sendable (String) -> Void) {
        self.out = out
        self.err = err
    }

    public static let standard = OutputSink(
        out: { FileHandle.standardOutput.write(Data($0.utf8)) },
        err: { FileHandle.standardError.write(Data($0.utf8)) })
}

/// Collects output for tests.
public final class CapturedOutput: Sendable {
    private let outBuffer = Mutex("")
    private let errBuffer = Mutex("")

    public init() {}

    public var sink: OutputSink {
        OutputSink(out: { text in self.outBuffer.withLock { $0 += text } },
                   err: { text in self.errBuffer.withLock { $0 += text } })
    }

    public var stdout: String { outBuffer.withLock { $0 } }
    public var stderr: String { errBuffer.withLock { $0 } }
}

public enum Output {
    @TaskLocal public static var sink: OutputSink = .standard

    static func line(_ text: String) {
        sink.out(text + "\n")
    }

    static func errorLine(_ text: String) {
        sink.err(text + "\n")
    }
}
