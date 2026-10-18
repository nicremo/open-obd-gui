import Foundation
import OBDCore

/// One line of an `openobd.capture/1` JSON Lines file.
public struct CaptureEntry: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case header
        case sent
        case received
        case failure
        case note
    }

    public var type: Kind
    /// Seconds since the start of the capture.
    public var t: Double?
    /// Command sent to the adapter.
    public var line: String?
    /// Adapter text, failure code or note.
    public var text: String?
    /// Adapter response time in milliseconds.
    public var ms: Double?
    public var format: String?
    public var tool: String?
    public var createdAt: String?
    public var link: String?

    public init(type: Kind, t: Double? = nil, line: String? = nil, text: String? = nil, ms: Double? = nil,
                format: String? = nil, tool: String? = nil, createdAt: String? = nil, link: String? = nil) {
        self.type = type
        self.t = t
        self.line = line
        self.text = text
        self.ms = ms
        self.format = format
        self.tool = tool
        self.createdAt = createdAt
        self.link = link
    }

    public static let formatName = "openobd.capture/1"
}

/// Appends capture entries to a file. Each entry is flushed immediately so a crash keeps the evidence.
public actor CaptureRecorder {
    public nonisolated let url: URL
    private let handle: FileHandle
    private let start = ContinuousClock.now
    private var closed = false

    public init(url: URL, tool: String, link: String) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw OBDError.io("Mitschnitt \(url.path) kann nicht angelegt werden")
        }
        let handle = try FileHandle(forWritingTo: url)
        let header = CaptureEntry(type: .header, format: CaptureEntry.formatName, tool: tool,
                                  createdAt: ISO8601DateFormatter().string(from: Date()), link: link)
        try handle.write(contentsOf: Self.encode(header))
        self.url = url
        self.handle = handle
    }

    public func recordSent(_ line: String) {
        write(CaptureEntry(type: .sent, t: elapsed(), line: line))
    }

    public func recordReceived(_ text: String, elapsed duration: Duration) {
        write(CaptureEntry(type: .received, t: elapsed(), text: text, ms: Double(duration.wholeMilliseconds)))
    }

    public func recordFailure(_ code: String) {
        write(CaptureEntry(type: .failure, t: elapsed(), text: code))
    }

    public func note(_ text: String) {
        write(CaptureEntry(type: .note, t: elapsed(), text: text))
    }

    public func close() {
        guard !closed else { return }
        closed = true
        try? handle.close()
    }

    private func elapsed() -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func write(_ entry: CaptureEntry) {
        guard !closed, let data = try? Self.encode(entry) else { return }
        try? handle.write(contentsOf: data)
    }

    static func encode(_ entry: CaptureEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(entry) + Data("\n".utf8)
    }

    public static func load(_ url: URL) throws -> [CaptureEntry] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        let entries = try text.split(separator: "\n").map { try decoder.decode(CaptureEntry.self, from: Data($0.utf8)) }
        guard entries.first?.type == .header, entries.first?.format == CaptureEntry.formatName else {
            throw OBDError.malformedResponse("\(url.lastPathComponent) ist kein openobd-Mitschnitt")
        }
        return entries
    }
}

/// Records every transaction of `base` before passing the result on.
public struct CapturingLink: AdapterLink {
    private let base: any AdapterLink
    private let recorder: CaptureRecorder

    public init(base: any AdapterLink, recorder: CaptureRecorder) {
        self.base = base
        self.recorder = recorder
    }

    public var label: String { base.label }

    public func transact(_ command: String, timeout: Duration) async throws -> LinkReply {
        await recorder.recordSent(command)
        do {
            let reply = try await base.transact(command, timeout: timeout)
            await recorder.recordReceived(reply.text, elapsed: reply.elapsed)
            return reply
        } catch let error as OBDError {
            await recorder.recordFailure(error.code)
            throw error
        }
    }

    public func close() async {
        await base.close()
        await recorder.close()
    }
}
