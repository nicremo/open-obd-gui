import Foundation
import OBDCore

/// One simulated control module answering OBD (if it is an emissions ECU) and read-only UDS services.
public struct VirtualECU: Sendable {
    public var name: String
    public var request: UInt32
    public var response: UInt32
    public var bus: BusKind
    public var answersOBD: Bool
    public var pids: [UInt8: SimSignal]
    /// Service 09 data after `49 <type>`, including the count byte.
    public var vehicleInfo: [UInt8: [UInt8]]
    public var storedDTCs: [UInt16]
    public var pendingDTCs: [UInt16]
    public var permanentDTCs: [UInt16]
    /// Service 02 data per PID for freeze frame 0.
    public var freezeFrame: [UInt8: [UInt8]]
    public var dids: [UInt16: [UInt8]]
    public var dtcs: [UDSDTC]
    /// DIDs answered with 7F 22 78 before the positive response.
    public var slowDIDs: Set<UInt16>

    public init(name: String, request: UInt32, bus: BusKind, answersOBD: Bool = false, pids: [UInt8: SimSignal] = [:],
                vehicleInfo: [UInt8: [UInt8]] = [:], storedDTCs: [UInt16] = [], pendingDTCs: [UInt16] = [],
                permanentDTCs: [UInt16] = [], freezeFrame: [UInt8: [UInt8]] = [:], dids: [UInt16: [UInt8]] = [:],
                dtcs: [UDSDTC] = [], slowDIDs: Set<UInt16> = []) {
        self.name = name
        self.request = request
        self.response = request + 8
        self.bus = bus
        self.answersOBD = answersOBD
        self.pids = pids
        self.vehicleInfo = vehicleInfo
        self.storedDTCs = storedDTCs
        self.pendingDTCs = pendingDTCs
        self.permanentDTCs = permanentDTCs
        self.freezeFrame = freezeFrame
        self.dids = dids
        self.dtcs = dtcs
        self.slowDIDs = slowDIDs
    }

    static let availabilityMask: UInt8 = 0xFF

    /// Messages this ECU sends for `payload`, in order. Empty means the ECU stays silent.
    public func respond(to payload: [UInt8], functional: Bool, time: Double) -> [[UInt8]] {
        guard let service = payload.first else { return [] }
        switch service {
        case 0x01:
            return answersOBD ? currentData(payload, time: time) : []
        case 0x02:
            guard answersOBD, payload.count == 3 else { return [] }
            let pid = payload[1]
            if J1979.isSupportQuery(pid) {
                guard let mask = supportMask(base: pid, supported: Set(freezeFrame.keys)) else { return [] }
                return [[0x42, pid, payload[2]] + mask]
            }
            guard let data = freezeFrame[pid] else { return [] }
            return [[0x42, pid, payload[2]] + data]
        case 0x03:
            return answersOBD ? [troubleCodes(0x43, storedDTCs)] : []
        case 0x07:
            return answersOBD ? [troubleCodes(0x47, pendingDTCs)] : []
        case 0x0A:
            return answersOBD ? [troubleCodes(0x4A, permanentDTCs)] : []
        case 0x09:
            return answersOBD ? vehicleInformation(payload) : []
        case 0x10, 0x19, 0x22, 0x3E:
            return functional ? [] : uds(payload)
        default:
            return functional ? [] : [[0x7F, service, 0x11]]
        }
    }

    func currentData(_ payload: [UInt8], time: Double) -> [[UInt8]] {
        guard payload.count == 2 else { return [] }
        let pid = payload[1]
        if J1979.isSupportQuery(pid) {
            guard let mask = supportMask(base: pid, supported: Set(pids.keys)) else { return [] }
            return [[0x41, pid] + mask]
        }
        guard let signal = pids[pid] else { return [] }
        return [[0x41, pid] + signal.bytes(at: time)]
    }

    /// Bit for PID base+0x20 is set when any higher PID exists, so the support chain continues.
    func supportMask(base: UInt8, supported: Set<UInt8>) -> [UInt8]? {
        if base > 0, !supported.contains(where: { $0 > base }) { return nil }
        var mask = [UInt8](repeating: 0, count: 4)
        for offset in 1...32 {
            let pid = Int(base) + offset
            let included = offset == 32 ? supported.contains { Int($0) > pid } : supported.contains(UInt8(pid))
            if included {
                mask[(offset - 1) / 8] |= 0x80 >> UInt8((offset - 1) % 8)
            }
        }
        return mask
    }

    func troubleCodes(_ responseService: UInt8, _ codes: [UInt16]) -> [UInt8] {
        [responseService, UInt8(codes.count)] + codes.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
    }

    func vehicleInformation(_ payload: [UInt8]) -> [[UInt8]] {
        guard payload.count == 2 else { return [] }
        let type = payload[1]
        if type == 0x00 {
            var mask = [UInt8](repeating: 0, count: 4)
            for key in vehicleInfo.keys where (1...32).contains(key) {
                mask[Int(key - 1) / 8] |= 0x80 >> ((key - 1) % 8)
            }
            return [[0x49, 0x00] + mask]
        }
        guard let data = vehicleInfo[type] else { return [] }
        return [[0x49, type] + data]
    }

    func uds(_ payload: [UInt8]) -> [[UInt8]] {
        switch payload[0] {
        case 0x22:
            guard payload.count == 3 else { return [[0x7F, 0x22, 0x13]] }
            let did = UInt16(payload[1]) << 8 | UInt16(payload[2])
            guard let value = dids[did] else { return [[0x7F, 0x22, 0x31]] }
            let positive: [UInt8] = [0x62, payload[1], payload[2]] + value
            return slowDIDs.contains(did) ? [[0x7F, 0x22, 0x78], positive] : [positive]
        case 0x19:
            guard payload.count >= 2 else { return [[0x7F, 0x19, 0x13]] }
            let mask = payload.count > 2 ? payload[2] : 0xFF
            let matching = dtcs.filter { $0.status.rawValue & mask & Self.availabilityMask != 0 }
            switch payload[1] {
            case 0x01:
                return [[0x59, 0x01, Self.availabilityMask, 0x01, UInt8(matching.count >> 8), UInt8(matching.count & 0xFF)]]
            case 0x02:
                return [[0x59, 0x02, Self.availabilityMask] + matching.flatMap { $0.bytes + [$0.status.rawValue] }]
            case 0x04, 0x06:
                guard payload.count == 6, let dtc = dtcs.first(where: { $0.bytes == Array(payload[2..<5]) }) else {
                    return [[0x7F, 0x19, 0x31]]
                }
                return [[0x59, payload[1]] + dtc.bytes + [dtc.status.rawValue]]
            default:
                return [[0x7F, 0x19, 0x12]]
            }
        case 0x3E:
            return payload.count == 2 && payload[1] == 0x80 ? [] : [[0x7E, 0x00]]
        case 0x10:
            return payload.count == 2 && payload[1] == 0x01 ? [[0x50, 0x01, 0x00, 0x32, 0x01, 0xF4]] : [[0x7F, 0x10, 0x12]]
        default:
            return [[0x7F, payload[0], 0x11]]
        }
    }
}
