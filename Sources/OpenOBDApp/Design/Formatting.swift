import Foundation
import OBDCore

/// German formatting for numbers and dates.
enum Fmt {
    static func number(_ value: Double) -> String {
        MeasuredValue.format(value)
    }

    static func voltage(_ value: Double?) -> String {
        value.map { "\(number($0)) V" } ?? "unbekannt"
    }

    static func kilometers(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "de_DE"))) + " km"
    }

    static func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(Locale(identifier: "de_DE")))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .shortened).locale(Locale(identifier: "de_DE")))
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().hour().minute().second().locale(Locale(identifier: "de_DE")))
    }
}
