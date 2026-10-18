import AdapterKit
import Foundation
import OBDCore

/// `AdapterLink` to a `VirtualAdapter`. Clearly labelled so no report can be mistaken for a real vehicle.
public struct SimulatedLink: AdapterLink {
    public let adapter: VirtualAdapter
    public let label: String

    public init(profile: VehicleProfile, identity: VirtualAdapterIdentity = .obdLinkEX) {
        adapter = VirtualAdapter(profile: profile, identity: identity)
        label = "simulator:\(profile.id)"
    }

    public func transact(_ command: String, timeout: Duration) async throws -> LinkReply {
        let start = ContinuousClock.now
        let text = await adapter.handle(command)
        guard text.hasSuffix(">") else { throw OBDError.timeout("Simulator ohne Prompt") }
        return LinkReply(text: String(text.dropLast()), elapsed: ContinuousClock.now - start)
    }

    public func close() async {}
}
