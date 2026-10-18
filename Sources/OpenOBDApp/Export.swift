import AppKit
import DiagnosticEngine
import OpenOBDAppCore
import SwiftUI
import UniformTypeIdentifiers

/// Saves the current report as JSON (schema openobd.report/1) or Markdown.
@MainActor
enum ReportExport {
    enum Format {
        case json
        case markdown

        var type: UTType { self == .json ? .json : UTType(filenameExtension: "md") ?? .plainText }
        var fileExtension: String { self == .json ? "json" : "md" }
    }

    static func suggestedName(_ report: VehicleReport, _ format: Format) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let vehicle = report.vehicle.vin ?? (report.meta.simulated ? "Simulator" : "Fahrzeug")
        return "OpenOBD_\(vehicle)_\(formatter.string(from: report.meta.createdAt)).\(format.fileExtension)"
    }

    static func data(_ report: VehicleReport, _ format: Format) throws -> Data {
        switch format {
        case .json: try ReportCoding.encode(report)
        case .markdown: Data(MarkdownExporter.render(report).utf8)
        }
    }

    static func save(_ report: VehicleReport, as format: Format) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = suggestedName(report, format)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data(report, format).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Bericht konnte nicht gespeichert werden."
            alert.runModal()
        }
    }

    static func copyMarkdown(_ report: VehicleReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MarkdownExporter.render(report), forType: .string)
    }
}

struct ExportMenu: View {
    let model: AppModel

    var body: some View {
        Menu {
            Button("Bericht als JSON sichern …") { model.report.map { ReportExport.save($0, as: .json) } }
            Button("Bericht als Markdown sichern …") { model.report.map { ReportExport.save($0, as: .markdown) } }
            Divider()
            Button("Bericht als Text kopieren") { model.report.map(ReportExport.copyMarkdown) }
        } label: {
            Label("Exportieren", systemImage: "square.and.arrow.up")
        }
        .disabled(model.report == nil)
        .help("Bericht sichern oder kopieren")
    }
}
