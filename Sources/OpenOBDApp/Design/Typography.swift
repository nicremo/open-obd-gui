import SwiftUI

/// Native SF Pro for all text; condensed SF Pro with tabular digits only for values, codes, module tags and the VIN;
/// SF Mono only for raw bytes.
extension Font {
    static func timing(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }

    // Native text: system font in the usual Mac sizes for titles, headings and prose.
    static let obdHero = Font.system(size: 26, weight: .bold)
    static let obdTitle = Font.headline
    static let obdHeadline = Font.system(size: 13, weight: .semibold)
    static let obdLabel = Font.system(size: 12, weight: .medium)
    static let obdBody = Font.system(size: 13)
    static let obdCaption = Font.system(size: 11)
    // Timing type only for numbers, module codes and trouble codes.
    static let obdValue = Font.timing(28, .bold)
    static let obdValueMedium = Font.timing(20, .bold)
    static let obdCode = Font.timing(15, .heavy)
    static let obdCodeLarge = Font.timing(30, .heavy)
    static let obdMono = Font.system(size: 12, design: .monospaced)
    static let obdMonoStrong = Font.timing(14, .heavy)
    static let obdMonoLarge = Font.system(size: 16, weight: .semibold, design: .monospaced)
}

/// 8 pt grid with the allowed steps.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum Radius {
    static let tile: CGFloat = 8
    static let control: CGFloat = 6
    static let tag: CGFloat = 3
}
