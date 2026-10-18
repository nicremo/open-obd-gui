import AdapterKit
import FordKnowledge
import Foundation
import OBDCore

public struct DiscoveredModule: Sendable, Codable, Equatable, Identifiable {
    public var bus: BusKind
    public var requestID: UInt32
    public var responseID: UInt32
    public var responseMilliseconds: Int
    /// Request that found the module, for example "3E 00".
    public var probe: String
    public var catalogAcronym: String?

    public var id: String { "\(bus.rawValue)-\(requestHex)" }
    public var requestHex: String { Hex.canID(requestID, extended: false) }
    public var responseHex: String { Hex.canID(responseID, extended: false) }
}

/// Finds Ford modules by probing diagnostic addresses on one bus with TesterPresent.
public struct ModuleDiscovery: Sendable {
    let driver: AdapterDriver
    let knowledge: KnowledgeBase

    public init(driver: AdapterDriver, knowledge: KnowledgeBase) {
        self.driver = driver
        self.knowledge = knowledge
    }

    /// Catalog addresses first. `sweep` additionally probes every address from 0x700 to 0x7F7 except 0x7DF.
    public func discover(on bus: BusKind, sweep: Bool, found: (@Sendable (DiscoveredModule) -> Void)? = nil) async throws -> [DiscoveredModule] {
        try await driver.selectBus(bus)
        let catalog = knowledge.catalogAddresses
        var candidates = catalog
        if sweep {
            candidates += (UInt32(0x700)...UInt32(0x7F7)).filter { $0 != 0x7DF && !catalog.contains($0) }
        }
        var modules: [DiscoveredModule] = []
        var responders = Set<UInt32>()
        for address in candidates where !responders.contains(address) {
            guard let module = try await probe(address, on: bus, withFallback: catalog.contains(address)) else { continue }
            guard responders.insert(module.responseID).inserted else { continue }
            modules.append(module)
            found?(module)
        }
        return modules
    }

    /// TesterPresent first. For catalog addresses a ReadDataByIdentifier F188 follows if TesterPresent stays silent.
    func probe(_ address: UInt32, on bus: BusKind, withFallback: Bool) async throws -> DiscoveredModule? {
        let probes: [[UInt8]] = withFallback ? [UDSCodec.testerPresent, UDSCodec.readDataByIdentifier(0xF188)] : [UDSCodec.testerPresent]
        for payload in probes {
            let result = try await driver.request(payload, to: .probe(request: address), timeout: .milliseconds(80), expectedResponses: 1)
            if let message = result.messages.first {
                return DiscoveredModule(
                    bus: bus,
                    requestID: address,
                    responseID: message.source.value,
                    responseMilliseconds: Int(result.elapsed.wholeMilliseconds),
                    probe: Hex.encode(payload, separator: " "),
                    catalogAcronym: knowledge.module(request: address)?.acronym)
            }
        }
        return nil
    }
}
