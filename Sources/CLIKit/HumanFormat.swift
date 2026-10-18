import AdapterKit
import DiagnosticEngine
import Foundation
import OBDCore

/// German terminal output. Machines use --json instead.
enum HumanFormat {
    static func voltage(_ value: Double?) -> String {
        value.map { "\(MeasuredValue.format($0)) V" } ?? "unbekannt"
    }

    static func devices(_ devices: [SerialDeviceCandidate]) -> String {
        guard !devices.isEmpty else {
            return "Kein passendes serielles Gerät gefunden. Ist der OBDLink EX per USB eingesteckt?"
        }
        var table = TextTable(headers: ["Port", "Gerät", "USB-ID", "Rang", "Begründung"])
        for device in devices {
            let usb = device.vendorID.map { String(format: "%04X:%04X", $0, device.productID ?? 0) } ?? ""
            table.add([device.path, device.productName ?? "", usb, String(device.rank), device.reason])
        }
        return table.render()
    }

    static func adapter(_ summary: AdapterSummary) -> String {
        var table = TextTable(headers: ["Merkmal", "Wert"])
        table.add(["Gerät", summary.identity.displayName])
        table.add(["ELM-Kennung", summary.identity.elmVersion])
        table.add(["Firmware", summary.identity.stnFirmware ?? "kein STN-Chip"])
        table.add(["Hersteller", summary.identity.manufacturer ?? "unbekannt"])
        table.add(["Spannung", voltage(summary.voltage)])
        table.add(["MS-CAN", summary.msCANAvailable ? "verfügbar" : "nicht verfügbar"])
        table.add(["Verbindung", summary.link + (summary.simulated ? " (Simulator)" : "")])
        return table.render()
    }

    static func codes(_ codes: [ReportDTC]) -> String {
        guard !codes.isEmpty else { return "Keine Fehlereinträge." }
        var table = TextTable(headers: ["Code", "Modul", "Zustand", "Dringlichkeit", "Bedeutung"])
        for code in codes.sorted(by: { ($0.severity, $1.displayCode) > ($1.severity, $0.displayCode) }) {
            table.add([code.displayCode, code.module, code.state, code.severity.german, code.title ?? "herstellerspezifisch, Bedeutung unbekannt"])
        }
        return table.render()
    }

    static func readings(_ readings: [DIDReading]) -> String {
        guard !readings.isEmpty else { return "Keine Kennungen." }
        var table = TextTable(headers: ["DID", "Name", "Wert"])
        for reading in readings {
            var value = reading.displayValue
            if let module = reading.partNumberModule { value += " (Basis \(reading.partNumber?.base ?? ""): \(module))" }
            table.add([reading.did, reading.name, value])
        }
        return table.render()
    }

    static func report(_ report: VehicleReport) -> String {
        var lines: [String] = []
        lines.append("Fahrzeug: \(report.vehicle.title)")
        lines.append("VIN:      \(report.vehicle.vin ?? "nicht gelesen")")
        lines.append("Adapter:  \(report.adapter.identity?.displayName ?? "unbekannt"), \(voltage(report.adapter.voltage))")
        lines.append("")
        lines.append(report.summary.headline)
        if !report.summary.highlights.isEmpty {
            lines += report.summary.highlights.map { "  - \($0)" }
        }
        lines += ["", "Fehlerspeicher", codes(report.allTroubleCodes)]
        lines += ["", "Steuergeräte (\(report.modules.count))"]
        if report.modules.isEmpty {
            lines.append("  keine gefunden")
        } else {
            var table = TextTable(headers: ["Bus", "Adresse", "Name", "Fehler"])
            for module in report.modules {
                let name = module.nameConfidence.isFact ? module.name : "\(module.name) (vermutlich)"
                table.add([module.bus.shortName, module.requestID, "\(module.acronym.map { "\($0) " } ?? "")\(name)", String(module.troubleCodes.count)])
            }
            lines.append(table.render())
        }
        if !report.findings.isEmpty {
            lines += ["", "Befunde"]
            lines += report.findings.map { "  - \($0.severity.german): \($0.text)" }
        }
        return lines.joined(separator: "\n")
    }
}
