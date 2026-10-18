import Foundation

/// CAN identifier with its addressing width.
public struct CANIdentifier: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let value: UInt32
    public let extended: Bool

    public init(_ value: UInt32, extended: Bool = false) {
        self.value = value
        self.extended = extended
    }

    public var description: String { Hex.canID(value, extended: extended) }

    public static func < (lhs: CANIdentifier, rhs: CANIdentifier) -> Bool {
        (lhs.extended ? 1 : 0, lhs.value) < (rhs.extended ? 1 : 0, rhs.value)
    }
}

/// One received CAN frame. `data` still contains the ISO-TP PCI byte(s).
public struct CANFrame: Hashable, Sendable {
    public let id: CANIdentifier
    public let data: [UInt8]

    public init(id: CANIdentifier, data: [UInt8]) {
        self.id = id
        self.data = data
    }
}

/// A complete ISO-TP message from one sender.
public struct ISOTPMessage: Hashable, Sendable, Codable {
    public let source: CANIdentifier
    public let payload: [UInt8]

    public init(source: CANIdentifier, payload: [UInt8]) {
        self.source = source
        self.payload = payload
    }
}

/// Reassembles ISO 15765-2 messages, one state per sender.
public struct ISOTPReassembler: Sendable {
    private struct Partial: Sendable {
        var expectedLength: Int
        var data: [UInt8]
        var nextSequence: UInt8
    }

    private var partials: [CANIdentifier: Partial] = [:]

    public init() {}

    public var incompleteSources: [CANIdentifier] { partials.keys.sorted() }

    public mutating func accept(_ frame: CANFrame) throws -> ISOTPMessage? {
        guard let pci = frame.data.first else {
            throw OBDError.malformedResponse("Leerer CAN-Rahmen von \(frame.id)")
        }
        switch pci >> 4 {
        case 0x0:
            let length = Int(pci & 0x0F)
            guard length > 0, frame.data.count > length else {
                throw OBDError.malformedResponse("Ungültiger Single Frame von \(frame.id): \(Hex.encode(frame.data, separator: " "))")
            }
            guard partials[frame.id] == nil else {
                throw OBDError.malformedResponse("Single Frame unterbricht eine Mehrfachnachricht von \(frame.id)")
            }
            return ISOTPMessage(source: frame.id, payload: Array(frame.data[1...length]))

        case 0x1:
            guard frame.data.count >= 2 else {
                throw OBDError.malformedResponse("Verkürzter First Frame von \(frame.id)")
            }
            let length = Int(pci & 0x0F) << 8 | Int(frame.data[1])
            guard length >= 8 else {
                throw OBDError.malformedResponse("First Frame mit unzulässiger Länge \(length) von \(frame.id)")
            }
            guard partials[frame.id] == nil else {
                throw OBDError.malformedResponse("Zweiter First Frame ohne Abschluss von \(frame.id)")
            }
            partials[frame.id] = Partial(
                expectedLength: length,
                data: Array(frame.data.dropFirst(2).prefix(length)),
                nextSequence: 1
            )
            return nil

        case 0x2:
            guard var partial = partials[frame.id] else {
                throw OBDError.malformedResponse("Consecutive Frame ohne First Frame von \(frame.id)")
            }
            let sequence = pci & 0x0F
            guard sequence == partial.nextSequence else {
                partials[frame.id] = nil
                throw OBDError.malformedResponse("ISO-TP-Sequenz \(sequence) statt \(partial.nextSequence) von \(frame.id)")
            }
            let missing = partial.expectedLength - partial.data.count
            partial.data.append(contentsOf: frame.data.dropFirst().prefix(missing))
            partial.nextSequence = (partial.nextSequence + 1) & 0x0F
            if partial.data.count >= partial.expectedLength {
                partials[frame.id] = nil
                return ISOTPMessage(source: frame.id, payload: partial.data)
            }
            partials[frame.id] = partial
            return nil

        case 0x3:
            // Flow control sent by an ECU. Irrelevant because requests are single frames.
            return nil

        default:
            throw OBDError.malformedResponse("Unbekanntes ISO-TP-PCI \(Hex.byteString(pci)) von \(frame.id)")
        }
    }

    public static func reassemble(_ frames: [CANFrame]) throws -> [ISOTPMessage] {
        var reassembler = ISOTPReassembler()
        var messages: [ISOTPMessage] = []
        for frame in frames {
            if let message = try reassembler.accept(frame) {
                messages.append(message)
            }
        }
        if let source = reassembler.incompleteSources.first {
            throw OBDError.malformedResponse("Unvollständige Mehrfachnachricht von \(source)")
        }
        return messages
    }
}
