import AppKit
import OpenOBDAppCore
import SwiftUI

/// Start arguments for demos and visual checks:
/// `--demo mondeo-mk4` connects to the simulator and scans, `--no-scan` skips the scan,
/// `--section faults` opens a section, `--appearance dark|light`, `--snapshot <dir>` renders every section and quits,
/// `--no-agent-bridge` keeps agents out (otherwise the app serves `openobd --via-app` on its socket).
@MainActor
enum LaunchActions {
    static func run(_ model: AppModel) async {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        switch value(after: "--appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        model.refreshDevices()
        model.refreshArchive()
        if !arguments.contains("--snapshot"), !arguments.contains("--no-agent-bridge") {
            model.startAgentBridge()
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { model.stopAgentBridge() }
            }
        }
        if let profile = value(after: "--demo") {
            await model.select(.simulator(profile))
            if !arguments.contains("--no-scan") {
                await model.scan()
            }
        }
        if let section = value(after: "--section").flatMap(AppSection.init(rawValue:)) {
            model.section = section
        }
        if let directory = value(after: "--snapshot") {
            await Snapshot.captureAll(model, into: URL(fileURLWithPath: directory))
            NSApp.terminate(nil)
        }
    }
}
