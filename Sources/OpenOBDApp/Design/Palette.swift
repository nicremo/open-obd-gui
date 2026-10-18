import AppKit
import DiagnosticEngine
import OBDCore
import SwiftUI

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// Color that follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
    }
}

/// Native first: every surface, separator and text color is a macOS semantic color, so light, dark and
/// increased contrast follow the system. The timing world lives in the flags, the numbers and the track map.
enum Palette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceRaised = Color.primary.opacity(0.05)
    static let hairline = Color(nsColor: .separatorColor)
    static let hairlineStrong = Color.primary.opacity(0.22)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .secondaryLabelColor)
    static let selection = Color.accentColor.opacity(0.16)

    // State colors for symbols, flags and lines. Words next to them stay in the label color.
    static let ok = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemYellow)
    /// Yellow for text: system yellow fails contrast on light grounds, so light mode uses a deep amber (5.4:1 on white).
    static let warningText = Color(light: 0x8A6100, dark: 0xFFD60A)
    /// Red and purple for text: the system tones fall below 4.5:1 for small text on light grounds.
    static let faultText = Color(light: 0xC4261F, dark: 0xFF453A)
    static let unverifiedText = Color(light: 0x7140D8, dark: 0xBF5AF2)
    static let high = Color(nsColor: .systemOrange)
    static let fault = Color(nsColor: .systemRed)
    static let live = Color(nsColor: .systemBlue)
    static let unverified = Color(nsColor: .systemPurple)

    // Bus traces on the track map.
    static let hsCAN = live
    static let msCAN = unverified

    // Car drawing, an illustration with its own two renditions.
    static let carBody = Color(light: 0xFFFFFF, dark: 0x1E242B)
    static let carBodyEdge = Color(light: 0x3A3F45, dark: 0x4A5562)
    static let carGlass = Color(light: 0xDDE2E8, dark: 0x0A0D10)
    static let carTyre = Color(light: 0x2A2F35, dark: 0x050607)
    static let glass = carGlass

    static func severity(_ severity: Severity?) -> Color {
        switch severity {
        case .critical: fault
        case .high: high
        case .medium: warning
        case .info: live
        case nil: ok
        }
    }

    static func confidence(_ confidence: Confidence) -> Color {
        switch confidence {
        case .standard, .verifiedOnVehicle: ok
        case .community: unverified
        case .unknown: textTertiary
        }
    }
}

/// Signal flags as they hang at the track, in the system colors. The defect flag keeps its black cloth.
enum FlagCloth {
    static let green = Color(nsColor: .systemGreen)
    static let blue = Color(nsColor: .systemBlue)
    static let yellow = Color(nsColor: .systemYellow)
    static let orange = Color(nsColor: .systemOrange)
    static let red = Color(nsColor: .systemRed)
    static let black = Color(nsColor: NSColor(rgb: 0x0B0C0E))
}
