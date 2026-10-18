import Foundation

/// Left aligned columns for terminal output. The last column is not padded.
struct TextTable {
    let headers: [String]
    private(set) var rows: [[String]] = []

    init(headers: [String]) {
        self.headers = headers
    }

    mutating func add(_ row: [String]) {
        rows.append(row)
    }

    func render(indent: Int = 2) -> String {
        var widths = headers.map(\.count)
        for row in rows {
            for (index, cell) in row.prefix(headers.count).enumerated() {
                widths[index] = max(widths[index], cell.count)
            }
        }
        func line(_ cells: [String]) -> String {
            let padded = cells.prefix(headers.count).enumerated().map { index, cell in
                index == headers.count - 1 ? cell : cell + String(repeating: " ", count: widths[index] - cell.count)
            }
            return String(repeating: " ", count: indent) + padded.joined(separator: "  ")
        }
        return ([line(headers)] + rows.map(line)).joined(separator: "\n")
    }
}
