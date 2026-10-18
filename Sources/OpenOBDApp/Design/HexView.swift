import OBDCore
import SwiftUI

/// Raw bytes with offset, groups of four and an ASCII column.
/// Bytes that make up the decoded value are highlighted.
struct HexView: View {
    let bytes: [UInt8]
    var highlight: Range<Int>?
    var bytesPerRow = 16

    init(bytes: [UInt8], highlight: Range<Int>? = nil) {
        self.bytes = bytes
        self.highlight = highlight
    }

    /// Accepts strings such as "41 0C 1A F8".
    init(hex: String, highlight: Range<Int>? = nil) {
        self.bytes = (try? Hex.decode(hex)) ?? []
        self.highlight = highlight
    }

    var body: some View {
        if bytes.isEmpty {
            StateLabel(state: .noResponse)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(stride(from: 0, to: bytes.count, by: bytesPerRow)), id: \.self) { offset in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                        Text(String(format: "%04X", offset)).foregroundStyle(Palette.textTertiary)
                        Text(hexLine(from: offset))
                        Text(asciiLine(from: offset)).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .font(.obdMono)
            .textSelection(.enabled)
            .accessibilityLabel("Rohbytes: \(Hex.encode(bytes, separator: " "))")
        }
    }

    private func hexLine(from offset: Int) -> AttributedString {
        var line = AttributedString()
        for index in offset..<min(offset + bytesPerRow, bytes.count) {
            var part = AttributedString(String(format: "%02X", bytes[index]))
            if highlight?.contains(index) == true {
                part.foregroundColor = Palette.live
                part.backgroundColor = Palette.live.opacity(0.16)
            } else {
                part.foregroundColor = Palette.textPrimary
            }
            line += part
            if index + 1 < min(offset + bytesPerRow, bytes.count) {
                line += AttributedString((index - offset) % 4 == 3 ? "  " : " ")
            }
        }
        return line
    }

    private func asciiLine(from offset: Int) -> String {
        String(bytes[offset..<min(offset + bytesPerRow, bytes.count)].map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." })
    }
}

/// Eight bits of a status byte with name and state.
struct BitTable: View {
    let byte: UInt8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Statusbyte").font(.obdLabel).foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("0x\(Hex.byteString(byte))  ·  \(String(byte, radix: 2).leftPadded(to: 8))")
                    .font(.obdMono)
                    .textSelection(.enabled)
            }
            Divider()
            ForEach(DTCStatus.bits.reversed(), id: \.index) { bit in
                let set = byte & (1 << UInt8(bit.index)) != 0
                HStack(spacing: Spacing.s) {
                    Text("Bit \(bit.index)").font(.obdMono).foregroundStyle(Palette.textTertiary).frame(width: 44, alignment: .leading)
                    Image(systemName: set ? "checkmark.square.fill" : "square")
                        .foregroundStyle(set ? Palette.live : Palette.textTertiary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(bit.german).font(.obdBody).foregroundStyle(set ? Palette.textPrimary : Palette.textSecondary)
                        Text(bit.name).font(.obdCaption).foregroundStyle(Palette.textTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Bit \(bit.index), \(bit.german), \(set ? "gesetzt" : "nicht gesetzt")")
            }
        }
    }
}

/// The eight status bits as one strip of cells, bit 7 on the left, like sector boxes on a timing screen.
/// Set bits are filled; the names of the set bits follow below.
struct StatusBitStrip: View {
    let byte: UInt8

    var body: some View {
        let bits = DTCStatus.bits.sorted { $0.index > $1.index }
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 2) {
                ForEach(bits, id: \.index) { bit in
                    let set = byte & (1 << UInt8(bit.index)) != 0
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(set ? Palette.textPrimary : Color.clear)
                            .frame(height: 10)
                            .overlay(Rectangle().strokeBorder(Palette.hairlineStrong, lineWidth: 1))
                        Text("\(bit.index)").font(.timing(10, .semibold)).foregroundStyle(set ? Palette.textPrimary : Palette.textTertiary)
                    }
                    .help("Bit \(bit.index): \(bit.german), \(set ? "gesetzt" : "nicht gesetzt")")
                }
                Text("0x\(Hex.byteString(byte))").font(.obdMono).foregroundStyle(Palette.textSecondary)
                    .fixedSize()
                    .padding(.leading, Spacing.s)
            }
            Text(bits.filter { byte & (1 << UInt8($0.index)) != 0 }.map(\.german).joined(separator: " · "))
                .font(.obdCaption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Statusbyte 0x\(Hex.byteString(byte))")
    }
}

extension String {
    func leftPadded(to length: Int, with character: Character = "0") -> String {
        count >= length ? self : String(repeating: character, count: length - count) + self
    }
}
