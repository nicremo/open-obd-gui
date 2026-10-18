import Foundation
import OBDCore

/// Versioned, validated knowledge about Ford modules, identifiers and trouble codes.
public struct KnowledgeBase: Sendable {
    public var modules: [ModuleDefinition]
    public var dids: [DIDDefinition]
    public var dtcTitles: [DTCTitle]
    public var dtcExplanations: [DTCExplanation]
    public var partNumberBases: [PartNumberBase]
    public var wmis: [WMIEntry]
    public var vehicles: [VehicleHint]

    /// The knowledge shipped with the app. Invalid resources are a build defect, tests guard against it.
    public static let bundled: KnowledgeBase = {
        do {
            let knowledge = try load(from: .module)
            try knowledge.validate()
            return knowledge
        } catch {
            preconditionFailure("FordKnowledge resources are invalid: \(error)")
        }
    }()

    private struct File<Item: Decodable>: Decodable {
        let schemaVersion: Int
        let items: [Item]
    }

    public static func load(from bundle: Bundle) throws -> KnowledgeBase {
        func read<Item: Decodable>(_ name: String, as: Item.Type) throws -> [Item] {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw KnowledgeError("Ressource \(name).json fehlt")
            }
            let file = try JSONDecoder().decode(File<Item>.self, from: Data(contentsOf: url))
            guard file.schemaVersion == 1 else {
                throw KnowledgeError("\(name).json hat Schema \(file.schemaVersion), erwartet 1")
            }
            return file.items
        }
        return KnowledgeBase(
            modules: try read("modules", as: ModuleDefinition.self),
            dids: try read("dids", as: DIDDefinition.self),
            dtcTitles: try read("dtc-titles-de", as: DTCTitle.self),
            dtcExplanations: try read("dtc-explanations-de", as: DTCExplanation.self),
            partNumberBases: try read("part-number-bases", as: PartNumberBase.self),
            wmis: try read("wmi", as: WMIEntry.self),
            vehicles: try read("vehicles", as: VehicleHint.self)
        )
    }

    // MARK: - Lookup

    public func module(request: UInt32) -> ModuleDefinition? {
        modules.first { $0.requestID == request }
    }

    public var catalogAddresses: [UInt32] {
        modules.map(\.requestID).sorted()
    }

    public func did(_ identifier: UInt16) -> DIDDefinition? {
        dids.first { $0.identifier == identifier }
    }

    public func title(for code: DTCCode) -> DTCTitle? {
        dtcTitles.first { $0.code == code.description }
    }

    public func explanation(for code: DTCCode) -> DTCExplanation? {
        dtcExplanations.first { $0.code == code.description }
    }

    public func partNumberBase(_ base: String) -> PartNumberBase? {
        partNumberBases.first { $0.base == base }
    }

    public func wmi(for vin: String) -> WMIEntry? {
        guard vin.count >= 3 else { return nil }
        return wmis.first { $0.wmi == String(vin.prefix(3)) }
    }

    public func vehicle(id: String) -> VehicleHint? {
        vehicles.first { $0.id == id }
    }

    // MARK: - Validation

    public func validate() throws {
        func unique(_ keys: [String], _ what: String) throws {
            var seen = Set<String>()
            for key in keys where !seen.insert(key).inserted {
                throw KnowledgeError("\(what): \(key) ist doppelt")
            }
        }
        func clean(_ texts: [String], _ what: String) throws {
            for text in texts {
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    throw KnowledgeError("\(what): leerer Text")
                }
                if text.contains("\u{2013}") || text.contains("\u{2014}") {
                    throw KnowledgeError("\(what): Gedankenstrich in \(text)")
                }
            }
        }

        try unique(modules.map(\.request), "modules")
        for module in modules {
            guard module.request.count == 3, Hex.parseCANID(module.request) != nil, (0x700...0x7F7).contains(module.requestID) else {
                throw KnowledgeError("modules: \(module.request) ist keine 11-Bit-Diagnoseadresse")
            }
            guard !module.buses.isEmpty else { throw KnowledgeError("modules: \(module.request) ohne Bus") }
            try clean([module.acronym, module.nameDE, module.nameEN, module.source], "modules \(module.request)")
        }

        try unique(dids.map(\.did), "dids")
        for did in dids {
            guard did.did.count == 4, Hex.isHexDigits(did.did) else { throw KnowledgeError("dids: \(did.did) ist keine DID") }
            try clean([did.nameDE, did.nameEN, did.source], "dids \(did.did)")
        }

        try unique(dtcTitles.map(\.code), "dtc-titles-de")
        for title in dtcTitles {
            guard DTCCode(title.code)?.description == title.code else { throw KnowledgeError("dtc-titles-de: \(title.code) ist kein DTC") }
            try clean([title.titleDE, title.source], "dtc-titles-de \(title.code)")
        }

        try unique(dtcExplanations.map(\.code), "dtc-explanations-de")
        let titled = Set(dtcTitles.map(\.code))
        for explanation in dtcExplanations {
            guard titled.contains(explanation.code) else {
                throw KnowledgeError("dtc-explanations-de: \(explanation.code) hat keinen Titel")
            }
            try clean([explanation.what, explanation.urgency, explanation.source] + explanation.causes, "dtc-explanations-de \(explanation.code)")
        }

        try unique(partNumberBases.map(\.base), "part-number-bases")
        for base in partNumberBases {
            try clean([base.base, base.acronym, base.nameDE, base.source], "part-number-bases")
        }

        try unique(wmis.map(\.wmi), "wmi")
        for entry in wmis {
            guard entry.wmi.count == 3 else { throw KnowledgeError("wmi: \(entry.wmi) hat nicht drei Zeichen") }
            try clean([entry.manufacturerDE, entry.source], "wmi \(entry.wmi)")
        }

        try unique(vehicles.map(\.id), "vehicles")
        for vehicle in vehicles {
            try clean([vehicle.nameDE, vehicle.years, vehicle.platform, vehicle.source] + vehicle.hints, "vehicles \(vehicle.id)")
        }
    }
}
