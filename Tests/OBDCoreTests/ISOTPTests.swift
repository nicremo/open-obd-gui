import Testing
@testable import OBDCore

@Suite struct ISOTPTests {
    let pcm = CANIdentifier(0x7E8)
    let tcm = CANIdentifier(0x7E9)

    @Test func singleFrameStripsPCIAndPadding() throws {
        let frame = CANFrame(id: pcm, data: [0x06, 0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13, 0x00])
        let messages = try ISOTPReassembler.reassemble([frame])
        #expect(messages == [ISOTPMessage(source: pcm, payload: [0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13])])
    }

    @Test func multiFrameMessageIsReassembled() throws {
        let payload: [UInt8] = [0x49, 0x02, 0x01] + Array("WF0DXXGBBDSM12345".utf8)
        #expect(payload.count == 20)
        let frames = [
            CANFrame(id: pcm, data: [0x10, 0x14] + payload[0..<6]),
            CANFrame(id: pcm, data: [0x21] + payload[6..<13]),
            CANFrame(id: pcm, data: [0x22] + payload[13..<20]),
        ]
        #expect(try ISOTPReassembler.reassemble(frames) == [ISOTPMessage(source: pcm, payload: payload)])
    }

    @Test func interleavedSourcesAreIndependent() throws {
        let long: [UInt8] = Array(0..<10)
        let frames = [
            CANFrame(id: pcm, data: [0x10, 0x0A] + long[0..<6]),
            CANFrame(id: tcm, data: [0x02, 0x7E, 0x00, 0, 0, 0, 0, 0]),
            CANFrame(id: pcm, data: [0x21] + long[6..<10] + [0, 0, 0]),
        ]
        let messages = try ISOTPReassembler.reassemble(frames)
        #expect(messages == [
            ISOTPMessage(source: tcm, payload: [0x7E, 0x00]),
            ISOTPMessage(source: pcm, payload: long),
        ])
    }

    @Test func sequenceNumberWrapsFromFToZero() throws {
        let length = 6 + 7 * 17
        let payload = (0..<length).map { UInt8($0 & 0xFF) }
        var frames = [CANFrame(id: pcm, data: [0x10 | UInt8(length >> 8), UInt8(length & 0xFF)] + payload[0..<6])]
        var offset = 6
        var sequence: UInt8 = 1
        while offset < length {
            let end = min(offset + 7, length)
            frames.append(CANFrame(id: pcm, data: [0x20 | sequence] + payload[offset..<end]))
            offset = end
            sequence = (sequence + 1) & 0x0F
        }
        #expect(try ISOTPReassembler.reassemble(frames) == [ISOTPMessage(source: pcm, payload: payload)])
    }

    @Test func wrongSequenceNumberThrows() {
        let frames = [
            CANFrame(id: pcm, data: [0x10, 0x0A, 1, 2, 3, 4, 5, 6]),
            CANFrame(id: pcm, data: [0x22, 7, 8, 9, 10, 0, 0, 0]),
        ]
        #expect(throws: OBDError.self) { try ISOTPReassembler.reassemble(frames) }
    }

    @Test func consecutiveFrameWithoutFirstFrameThrows() {
        #expect(throws: OBDError.self) {
            try ISOTPReassembler.reassemble([CANFrame(id: pcm, data: [0x21, 1, 2, 3, 4, 5, 6, 7])])
        }
    }

    @Test func incompleteMultiFrameThrows() {
        #expect(throws: OBDError.self) {
            try ISOTPReassembler.reassemble([CANFrame(id: pcm, data: [0x10, 0x14, 1, 2, 3, 4, 5, 6])])
        }
    }

    @Test func singleFrameLongerThanDataThrows() {
        #expect(throws: OBDError.self) {
            try ISOTPReassembler.reassemble([CANFrame(id: pcm, data: [0x07, 0x41])])
        }
    }

    @Test func zeroLengthSingleFrameThrows() {
        #expect(throws: OBDError.self) {
            try ISOTPReassembler.reassemble([CANFrame(id: pcm, data: [0x00, 0, 0, 0, 0, 0, 0, 0])])
        }
    }

    @Test func flowControlFramesAreIgnored() throws {
        let frames = [
            CANFrame(id: pcm, data: [0x30, 0x00, 0x00, 0, 0, 0, 0, 0]),
            CANFrame(id: pcm, data: [0x02, 0x7E, 0x00, 0, 0, 0, 0, 0]),
        ]
        #expect(try ISOTPReassembler.reassemble(frames) == [ISOTPMessage(source: pcm, payload: [0x7E, 0x00])])
    }

    @Test func identifiersSortAndPrint() {
        #expect(CANIdentifier(0x7E8) < CANIdentifier(0x7E9))
        #expect(CANIdentifier(0x7FF) < CANIdentifier(0x100, extended: true))
        #expect(CANIdentifier(0x18DAF110, extended: true).description == "18DAF110")
    }
}
