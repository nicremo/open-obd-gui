import DiagnosticEngine
import Foundation
import OBDCore

/// Short form of a report for agents (`openobd.digest/1`): what is wrong, where, how urgent. Facts only,
/// every title keeps its confidence. The full report stays available with `digest` off.
struct ReportDigest: Encodable, Sendable {
    struct Fault: Encodable, Sendable {
        let module: String
        let moduleName: String?
        let code: String
        let title: String?
        let titleConfidence: Confidence?
        let severity: Severity
        let state: String
        let sources: [ReportDTC.Source]
        let severityReasons: [String]
    }

    struct Module: Encodable, Sendable {
        let bus: BusKind
        let request: String
        let acronym: String?
        let name: String
        let nameConfidence: Confidence
        let faultCount: Int
        let issues: [String]
    }

    let schema = "openobd.digest/1"
    let vehicle: String
    let vin: String?
    let createdAt: Date
    let depth: ScanDepth
    let simulated: Bool
    let link: String
    let headline: String
    let highlights: [String]
    let milOn: Bool?
    let moduleCount: Int
    let faultCount: Int
    let bySeverity: [String: Int]
    let faults: [Fault]
    let modules: [Module]
    let findings: [Finding]
    let warnings: [String]

    init(_ report: VehicleReport) {
        let names = Dictionary(report.modules.map { ($0.requestID, [$0.acronym, $0.name].compactMap { $0 }.joined(separator: " ")) },
                               uniquingKeysWith: { first, _ in first })
        let groups = FaultGroup.groups(from: report)
        vehicle = report.vehicle.title
        vin = report.vehicle.vin
        createdAt = report.meta.createdAt
        depth = report.meta.depth
        simulated = report.meta.simulated
        link = report.meta.link
        headline = report.summary.headline
        highlights = report.summary.highlights
        milOn = report.summary.milOn
        moduleCount = report.summary.moduleCount
        faultCount = report.summary.faultCount
        bySeverity = report.summary.bySeverity
        faults = groups.map { group in
            let primary = group.primary
            return Fault(module: group.module, moduleName: names[group.module],
                         code: primary.displayCode, title: primary.title, titleConfidence: primary.titleConfidence,
                         severity: group.severity, state: group.isActive ? "aktiv" : primary.state, sources: group.sources,
                         severityReasons: primary.severityReasons)
        }
        modules = report.modules.map { module in
            Module(bus: module.bus, request: module.requestID, acronym: module.acronym, name: module.name, nameConfidence: module.nameConfidence,
                   faultCount: groups.filter { $0.module == module.requestID }.count, issues: module.issues)
        }
        findings = report.findings
        warnings = report.warnings
    }
}

/// A report as `data`: complete or as digest, encoded without a wrapper.
enum ReportPayload: Encodable, Sendable {
    case full(VehicleReport)
    case digest(ReportDigest)

    init(_ report: VehicleReport, digest: Bool) {
        self = digest ? .digest(ReportDigest(report)) : .full(report)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .full(let report): try container.encode(report)
        case .digest(let digest): try container.encode(digest)
        }
    }
}
