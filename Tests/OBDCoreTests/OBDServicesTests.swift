import Testing
@testable import OBDCore

@Suite struct OBDServicesTests {
    let vin = "WF0DXXGBBDSM12345"

    @Test func validatesVINCharacters() {
        #expect(OBDVehicleInfo.isValidVIN(vin))
        #expect(!OBDVehicleInfo.isValidVIN("WF0DXXGBBDSM1234"))
        #expect(!OBDVehicleInfo.isValidVIN("WF0DXXGBBDSI12345"))
        #expect(!OBDVehicleInfo.isValidVIN("WF0DXXGBBDSO12345"))
        #expect(!OBDVehicleInfo.isValidVIN("WF0DXXGBBDSQ12345"))
    }

    @Test func decodesVINWithCountByte() throws {
        #expect(try OBDVehicleInfo.decodeVIN([0x01] + Array(vin.utf8)) == vin)
    }

    @Test func decodesVINWithLeadingPadding() throws {
        #expect(try OBDVehicleInfo.decodeVIN([0x01, 0x00, 0x00, 0x00] + Array(vin.utf8)) == vin)
    }

    @Test func rejectsInvalidVIN() {
        #expect(throws: OBDError.self) { try OBDVehicleInfo.decodeVIN([0x01] + Array("SHORT".utf8)) }
        #expect(throws: OBDError.self) { try OBDVehicleInfo.decodeVIN([0x01] + Array("WF0DXXGBBDSI12345".utf8)) }
    }

    @Test func decodesCalibrationIDs() throws {
        let first = Array("BG91-12A650-AFF".utf8) + [0x00]
        let second = Array("CALIBRATION2    ".utf8)
        #expect(try OBDVehicleInfo.decodeCalibrationIDs([0x02] + first + second) == ["BG91-12A650-AFF", "CALIBRATION2"])
        #expect(throws: OBDError.self) { try OBDVehicleInfo.decodeCalibrationIDs([0x01] + Array("SHORT".utf8)) }
    }

    @Test func nonPrintableCalibrationIDIsHex() throws {
        let raw: [UInt8] = [0x01] + Array(repeating: 0x01, count: 16)
        #expect(try OBDVehicleInfo.decodeCalibrationIDs(raw) == [String(repeating: "01", count: 16)])
    }

    @Test func decodesCVNs() throws {
        #expect(try OBDVehicleInfo.decodeCVNs([0x02, 0x12, 0x34, 0xAB, 0xCD, 0x00, 0x00, 0x00, 0x01]) == ["1234ABCD", "00000001"])
        #expect(throws: OBDError.self) { try OBDVehicleInfo.decodeCVNs([0x01, 0x12, 0x34]) }
    }

    @Test func decodesECUName() throws {
        let name = Array("ECM-EngineControl".utf8) + [0x00, 0x00, 0x00]
        #expect(name.count == 20)
        #expect(try OBDVehicleInfo.decodeECUName([0x01] + name) == "ECM-EngineControl")
    }

    @Test func decodesSupportedInfoTypes() throws {
        #expect(try OBDVehicleInfo.supportedInfoTypes([0x55, 0x40, 0x00, 0x00]) == [0x02, 0x04, 0x06, 0x08, 0x0A])
    }

    @Test func decodesStoredTroubleCodes() throws {
        let codes = try OBDTroubleCodes.decode([0x43, 0x02, 0x04, 0x01, 0x01, 0x33], service: 0x03)
        #expect(codes.map(\.description) == ["P0401", "P0133"])
    }

    @Test func emptyAndPaddedListsAreValid() throws {
        #expect(try OBDTroubleCodes.decode([0x43, 0x00], service: 0x03).isEmpty)
        #expect(try OBDTroubleCodes.decode([0x47, 0x01, 0x00, 0x00], service: 0x07).isEmpty)
        #expect(try OBDTroubleCodes.decode([0x4A, 0x01, 0xC1, 0x00], service: 0x0A).map(\.description) == ["U0100"])
    }

    @Test func rejectsMismatchedTroubleCodeResponses() {
        #expect(throws: OBDError.self) { try OBDTroubleCodes.decode([0x43, 0x02, 0x04, 0x01], service: 0x03) }
        #expect(throws: OBDError.self) { try OBDTroubleCodes.decode([0x47, 0x00], service: 0x03) }
        #expect(throws: OBDError.self) { try OBDTroubleCodes.decode([0x43], service: 0x03) }
    }
}
