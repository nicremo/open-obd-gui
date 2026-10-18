import Foundation

/// One fault as a person sees it: the same code in the same module, reported by one or more sources
/// (OBD stored, pending, permanent and the module's own UDS memory).
public struct FaultGroup: Identifiable, Sendable, Equatable {
    public let module: String
    public let code: String
    public let entries: [ReportDTC]

    public var id: String { "\(module)-\(code)" }

    /// Entry with the most detail: highest severity, UDS before OBD.
    public var primary: ReportDTC {
        entries.max { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            return lhs.source != .uds && rhs.source == .uds
        } ?? entries[0]
    }

    public var severity: Severity { primary.severity }
    public var sources: [ReportDTC.Source] { entries.map(\.source) }
    public var isActive: Bool { entries.contains { $0.state == "aktiv" } }

    public init(module: String, code: String, entries: [ReportDTC]) {
        precondition(!entries.isEmpty, "a fault group needs at least one entry")
        self.module = module
        self.code = code
        self.entries = entries
    }

    /// Groups all codes of a report, most urgent first.
    public static func groups(from report: VehicleReport) -> [FaultGroup] {
        groups(from: report.allTroubleCodes)
    }

    public static func groups(from codes: [ReportDTC]) -> [FaultGroup] {
        var order: [String] = []
        var buckets: [String: [ReportDTC]] = [:]
        for code in codes {
            let key = "\(code.module)-\(code.code)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(code)
        }
        let groups = order.compactMap { key in
            buckets[key].map { FaultGroup(module: $0[0].module, code: $0[0].code, entries: $0) }
        }
        return groups.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            if lhs.module != rhs.module { return lhs.module < rhs.module }
            return lhs.code < rhs.code
        }
    }
}
