import Foundation

/// Saved reports in `~/Library/Application Support/Open OBD GUI/Reports/<VIN>/`, shared by app, CLI and MCP.
public struct ReportStore: Sendable {
    public static let environmentKey = "OPENOBD_REPORTS_DIR"

    public struct Entry: Identifiable, Sendable, Hashable, Codable {
        public let url: URL
        public let title: String
        public let vin: String?
        public let date: Date
        public let headline: String
        public let simulated: Bool
        public let faultCount: Int

        public var id: URL { url }
    }

    public let directory: URL

    /// Without a directory the store uses `OPENOBD_REPORTS_DIR`, otherwise the app's folder.
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let override = ProcessInfo.processInfo.environment[Self.environmentKey], !override.isEmpty {
            self.directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Open OBD GUI/Reports", isDirectory: true)
        }
    }

    @discardableResult
    public func save(_ report: VehicleReport) throws -> URL {
        let folderName = report.meta.simulated ? "Simulator" : (report.vehicle.vin ?? "unbekannt")
        let folder = directory.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let url = folder.appendingPathComponent("\(formatter.string(from: report.meta.createdAt)).json")
        try ReportCoding.encode(report).write(to: url, options: .atomic)
        return url
    }

    /// Newest first.
    public func list() -> [Entry] {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects as? [URL] else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Entry? in
                guard let report = try? load(url) else { return nil }
                return Entry(url: url, title: report.vehicle.title, vin: report.vehicle.vin, date: report.meta.createdAt,
                             headline: report.summary.headline, simulated: report.meta.simulated, faultCount: report.summary.faultCount)
            }
            .sorted { $0.date > $1.date }
    }

    /// The newest saved report, if any.
    public func latest() -> (entry: Entry, report: VehicleReport)? {
        for entry in list() {
            if let report = try? load(entry.url) { return (entry, report) }
        }
        return nil
    }

    public func load(_ url: URL) throws -> VehicleReport {
        try ReportCoding.decode(Data(contentsOf: url))
    }
}
