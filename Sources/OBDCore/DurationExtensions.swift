import Foundation

extension Duration {
    /// Whole milliseconds, truncated toward zero.
    public var wholeMilliseconds: Int64 {
        let parts = components
        return parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000
    }
}
