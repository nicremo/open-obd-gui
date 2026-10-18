import AppKit
import DiagnosticEngine
import OBDCore
import OpenOBDAppCore
import SwiftUI

/// Renders the main window of every section to PNG. No screen recording permission needed.
@MainActor
enum Snapshot {
    static func captureAll(_ model: AppModel, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first else { return }
        let size = windowSize()
        window.setFrame(NSRect(x: 80, y: 80, width: size.width, height: size.height), display: true)
        // An inactive window draws its sidebar material dark; captures must show the active state.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let scheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        for (index, section) in AppSection.allCases.enumerated() {
            model.showInspector = false
            model.section = section
            if section == .live {
                await model.startLive()
                try? await Task.sleep(for: .seconds(3))
            }
            if section == .workshop {
                _ = await model.raw("22 F1 90", module: "7E0", bus: .hsCAN, functional: false)
            }
            try? await Task.sleep(for: .milliseconds(900))
            capture(window, to: directory.appendingPathComponent("\(index + 1)-\(section.rawValue)-\(scheme).png"))
            if section == .live {
                model.stopLive()
            }
        }
        if let report = model.report, let code = FaultGroup.groups(from: report).first?.primary {
            model.section = .faults
            model.inspect(.troubleCode(code))
            try? await Task.sleep(for: .milliseconds(1800))
            capture(window, to: directory.appendingPathComponent("8-faults-inspector-\(scheme).png"))
            model.section = .cockpit
            try? await Task.sleep(for: .milliseconds(900))
            capture(window, to: directory.appendingPathComponent("9-cockpit-inspector-\(scheme).png"))
            model.section = .modules
            try? await Task.sleep(for: .milliseconds(1500))
            capture(window, to: directory.appendingPathComponent("10-modules-inspector-\(scheme).png"))
        }
    }

    /// `--window-size 1080x700` checks the minimum layout. Default is a 15 inch MacBook window.
    static func windowSize() -> CGSize {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--window-size"), index + 1 < arguments.count else { return CGSize(width: 1440, height: 900) }
        let parts = arguments[index + 1].split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 1440, height: 900)
    }

    /// Uses the window server first, which also renders glass materials. Falls back to drawing the view hierarchy.
    static func capture(_ window: NSWindow, to url: URL) {
        for attempt in 0..<3 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
            if (try? process.run()) != nil {
                process.waitUntilExit()
                if process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) { return }
            }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.4) }
        }
        FileHandle.standardError.write(Data("screencapture failed for \(url.lastPathComponent), drawing the view hierarchy instead\n".utf8))
        guard let view = window.contentView, let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        try? representation.representation(using: .png, properties: [:])?.write(to: url)
    }
}
