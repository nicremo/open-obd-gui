import Foundation
import OBDCore

/// Checks every command against `CommandPolicy` before it reaches the underlying link.
public struct SafeLink: AdapterLink {
    private let base: any AdapterLink

    public init(_ base: any AdapterLink) {
        self.base = base
    }

    public var label: String { base.label }

    public func transact(_ command: String, timeout: Duration) async throws -> LinkReply {
        try CommandPolicy.validate(command)
        return try await base.transact(command, timeout: timeout)
    }

    public func close() async {
        await base.close()
    }
}
