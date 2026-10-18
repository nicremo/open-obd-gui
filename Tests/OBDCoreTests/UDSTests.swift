import Testing
@testable import OBDCore

@Suite struct UDSTests {
    @Test func classifiesPositiveNegativeAndPending() throws {
        #expect(try UDSResponse.classify([0x62, 0xF1, 0x90, 0x41], service: 0x22) == .positive(data: [0xF1, 0x90, 0x41]))
        #expect(try UDSResponse.classify([0x7F, 0x22, 0x31], service: 0x22) == .negative(code: 0x31))
        #expect(try UDSResponse.classify([0x7F, 0x22, 0x78], service: 0x22) == .pending)
        #expect(try UDSResponse.classify([0x7E, 0x00], service: 0x3E) == .positive(data: [0x00]))
    }

    @Test func rejectsMismatchedResponses() {
        #expect(throws: OBDError.self) { try UDSResponse.classify([], service: 0x22) }
        #expect(throws: OBDError.self) { try UDSResponse.classify([0x59, 0x02], service: 0x22) }
        #expect(throws: OBDError.self) { try UDSResponse.classify([0x7F, 0x19, 0x31], service: 0x22) }
        #expect(throws: OBDError.self) { try UDSResponse.classify([0x7F, 0x22], service: 0x22) }
    }

    @Test func buildsRequestsThatPassThePolicy() throws {
        let requests: [[UInt8]] = [
            UDSCodec.readDataByIdentifier(0xF190),
            UDSCodec.testerPresent,
            UDSCodec.reportDTCByStatusMask(),
            UDSCodec.reportNumberOfDTCByStatusMask(),
            UDSCodec.reportSnapshotRecord(UDSDTC(high: 0x04, middle: 0x01, low: 0x00, status: []), record: 0xFF),
            UDSCodec.reportExtendedDataRecord(UDSDTC(high: 0x04, middle: 0x01, low: 0x00, status: []), record: 0xFF),
        ]
        #expect(requests[0] == [0x22, 0xF1, 0x90])
        #expect(requests[4] == [0x19, 0x04, 0x04, 0x01, 0x00, 0xFF])
        for request in requests { try ReadOnlyPolicy.validate(request) }
    }

    @Test func decodesReadDataByIdentifier() throws {
        #expect(try UDSCodec.decodeReadDataByIdentifier([0xF1, 0x90, 0x57, 0x46], did: 0xF190) == [0x57, 0x46])
        #expect(try UDSCodec.decodeReadDataByIdentifier([0xF1, 0x90], did: 0xF190) == [])
        #expect(throws: OBDError.self) { try UDSCodec.decodeReadDataByIdentifier([0xF1, 0x88, 0x00], did: 0xF190) }
        #expect(throws: OBDError.self) { try UDSCodec.decodeReadDataByIdentifier([0xF1], did: 0xF190) }
    }

    @Test func decodesDTCListAndSkipsEmptyRecords() throws {
        let data: [UInt8] = [0x02, 0xFF, 0x04, 0x01, 0x00, 0x2F, 0xC1, 0x00, 0x87, 0x28, 0x00, 0x00, 0x00, 0x00]
        let list = try UDSCodec.decodeDTCByStatusMask(data)
        #expect(list.availabilityMask == DTCStatus(rawValue: 0xFF))
        #expect(list.dtcs.map(\.displayCode) == ["P0401-00", "U0100-87"])
        #expect(list.dtcs[1].status == DTCStatus(rawValue: 0x28))
    }

    @Test func emptyDTCListIsValid() throws {
        #expect(try UDSCodec.decodeDTCByStatusMask([0x02, 0x7F]).dtcs.isEmpty)
    }

    @Test func rejectsTruncatedDTCList() {
        #expect(throws: OBDError.self) { try UDSCodec.decodeDTCByStatusMask([0x02, 0xFF, 0x04, 0x01, 0x00]) }
        #expect(throws: OBDError.self) { try UDSCodec.decodeDTCByStatusMask([0x01, 0xFF]) }
    }

    @Test func decodesDTCCount() throws {
        let count = try UDSCodec.decodeDTCCount([0x01, 0x7F, 0x01, 0x00, 0x03])
        #expect(count == UDSCodec.DTCCount(availabilityMask: DTCStatus(rawValue: 0x7F), formatIdentifier: 0x01, count: 3))
        #expect(throws: OBDError.self) { try UDSCodec.decodeDTCCount([0x01, 0x7F, 0x01, 0x00]) }
    }
}
