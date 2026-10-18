import Foundation
import OBDCore

/// German Markdown report for people and workshops.
public enum MarkdownExporter {
    public static func render(_ report: VehicleReport) -> String {
        var lines: [String] = []
        let seconds = MeasuredValue.format(Double(report.meta.durationMilliseconds) / 1000)
        lines.append("# Fahrzeugbericht: \(report.vehicle.title)")
        lines.append("")
        lines.append("Erstellt am \(date(report.meta.createdAt)) mit \(report.meta.tool), Tiefe \(report.meta.depth.german), Dauer \(seconds) s.")
        if report.meta.simulated {
            lines += ["", "> Simulator: Diese Daten stammen nicht von einem echten Fahrzeug."]
        }

        lines += ["", "## Zusammenfassung", "", "**\(report.summary.headline)**", ""]
        lines += report.summary.highlights.map { "- \($0)" }

        lines += ["", "## Fahrzeug", ""]
        var vehicleRows: [[String]] = [["Bezeichnung", report.vehicle.title], ["Fahrgestellnummer", report.vehicle.vin ?? "nicht gelesen"]]
        if let info = report.vehicle.vinInfo {
            vehicleRows.append(["Hersteller (WMI \(info.wmi))", info.manufacturer ?? "unbekannt"])
            vehicleRows.append(["Region", info.region])
            vehicleRows.append(["Modelljahr", info.modelYearCandidates.isEmpty ? info.modelYearNote : info.modelYearCandidates.map(String.init).joined(separator: " oder ")])
        }
        lines += table(["Merkmal", "Wert"], vehicleRows)

        if !report.findings.isEmpty {
            lines += ["", "## Befunde", ""]
            lines += report.findings.map { "- **\($0.severity.german):** \($0.text) _(\($0.evidence))_" }
        }

        lines += ["", "## Fehlerspeicher", ""]
        let codes = report.allTroubleCodes
        if codes.isEmpty {
            lines.append("Keine Fehlereinträge.")
        } else {
            lines += table(["Code", "Steuergerät", "Bedeutung", "Zustand", "Dringlichkeit"], codes.map { code in
                [code.displayCode, moduleLabel(code.module, in: report), code.title ?? "herstellerspezifisch, Bedeutung unbekannt", code.state, code.severity.german]
            })
            for code in codes where code.explanation != nil {
                if let explanation = code.explanation {
                    lines += ["", "### \(code.displayCode)", "", explanation.what, "", "Dringlichkeit: \(explanation.urgency)"]
                    lines += explanation.causes.map { "- \($0)" }
                }
            }
        }

        lines += ["", "## Steuergeräte", ""]
        if report.modules.isEmpty {
            lines.append("Keine Steuergeräte gefunden.")
        } else {
            lines += table(["Bus", "Adresse", "Name", "Teilenummer", "Fehler", "Antwort"], report.modules.map { module in
                let part = module.identification.first { $0.partNumber != nil }?.partNumber?.text ?? ""
                return [module.bus.shortName, "\(module.requestID) / \(module.responseID)", nameLabel(module), part,
                        String(module.troubleCodes.count), "\(module.responseMilliseconds) ms"]
            })
        }

        for ecu in report.obd.ecus {
            lines += ["", "## OBD-Steuergerät \(ecu.address)", ""]
            if let readiness = ecu.readiness {
                lines.append("Motorkontrollleuchte: \(readiness.milOn == true ? "an" : "aus"), Zündart: \(readiness.ignition.german).")
                lines += [""] + table(["Bereitschaftstest", "Zustand"], readiness.supportedMonitors.map { [$0.name, $0.stateGerman] })
            }
            if !ecu.snapshot.isEmpty {
                lines += ["", "Messwerte:", ""]
                lines += table(["Messwert", "Wert"], ecu.snapshot.flatMap { record in record.fields.map { [$0.label, $0.value.displayText] } })
            }
        }

        lines += ["", "## Adapter", ""]
        let identity = report.adapter.identity
        lines += table(["Merkmal", "Wert"], [
            ["Gerät", identity?.displayName ?? "unbekannt"],
            ["Firmware", identity?.stnFirmware ?? identity?.elmVersion ?? "unbekannt"],
            ["Spannung", report.adapter.voltage.map { "\(MeasuredValue.format($0)) V" } ?? "nicht gemessen"],
            ["Verbindung", report.meta.link],
        ])

        lines += ["", "## Ablauf", ""]
        lines += table(["Schritt", "Ergebnis", "Dauer", "Details"], report.meta.steps.map { step in
            [step.title, outcome(step.outcome), "\(step.durationMilliseconds) ms", step.detail]
        })

        if !report.warnings.isEmpty {
            lines += ["", "## Hinweise", ""]
            lines += report.warnings.map { "- \($0)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func table(_ header: [String], _ rows: [[String]]) -> [String] {
        func row(_ cells: [String]) -> String {
            "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }.joined(separator: " | ") + " |"
        }
        return [row(header), row(header.map { _ in "---" })] + rows.map(row)
    }

    static func nameLabel(_ module: ReportModule) -> String {
        module.nameConfidence.isFact ? module.name : "\(module.name) (vermutlich)"
    }

    static func moduleLabel(_ address: String, in report: VehicleReport) -> String {
        if let module = report.modules.first(where: { $0.requestID == address }) {
            return "\(module.acronym ?? module.name) (\(address))"
        }
        return "OBD \(address)"
    }

    static func outcome(_ outcome: StepRecord.Outcome) -> String {
        switch outcome {
        case .ok: "erledigt"
        case .skipped: "übersprungen"
        case .failed: "fehlgeschlagen"
        }
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
