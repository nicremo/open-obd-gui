import Foundation
import OBDCore

extension VehicleProfile {
    /// Synthetic VIN, `SM` marks the simulator.
    public static let mondeoVIN = "WF0DXXGBBDSM12345"

    /// Synthetic Ford Mondeo Mk4 2.0 TDCi: diesel readiness, HS-CAN powertrain and safety, MS-CAN comfort modules.
    public static let mondeoMk4 = VehicleProfile(
        id: "mondeo-mk4",
        title: "Ford Mondeo Mk4 2.0 TDCi (Simulator)",
        note: "Synthetisches Profil. Struktur plausibel, Werte erfunden.",
        batteryVoltage: 12.6,
        ecus: [
            VirtualECU(
                name: "PCM", request: 0x7E0, bus: .hsCAN, answersOBD: true,
                pids: [
                    0x01: .constant([0x81, 0x0F, 0xE9, 0x08]),
                    0x04: .wave(18, 55, period: 9, encode: SimEncode.percent),
                    0x05: .wave(86, 91, period: 120, encode: SimEncode.temperature),
                    0x0B: .wave(101, 165, period: 9, encode: SimEncode.plain),
                    0x0C: .wave(790, 2350, period: 9, encode: SimEncode.rpm),
                    0x0D: .wave(0, 72, period: 30, encode: SimEncode.plain),
                    0x0F: .constant([0x41]),
                    0x10: .wave(9, 42, period: 9, encode: SimEncode.airflow),
                    0x1C: .constant([0x06]),
                    0x1F: .constant([0x02, 0x58]),
                    0x21: .constant([0x00, 0x2A]),
                    0x23: .wave(28_000, 110_000, period: 9, encode: SimEncode.railPressure),
                    0x2C: .wave(5, 45, period: 14, encode: SimEncode.percent),
                    0x30: .constant([0x0C]),
                    0x31: .constant([0x04, 0xD2]),
                    0x33: .constant([0x62]),
                    0x42: .wave(13.9, 14.3, period: 20, encode: SimEncode.voltage),
                    0x46: .constant([0x3C]),
                    0x49: .wave(14, 38, period: 9, encode: SimEncode.percent),
                ],
                vehicleInfo: [
                    0x02: [0x01] + ascii(mondeoVIN),
                    0x04: [0x01] + ascii("SIM1-12A650-AA\0\0"),
                    0x06: [0x01, 0x5A, 0x3C, 0x11, 0x08],
                    0x0A: [0x01] + ascii("ECM-EngineControl\0\0\0"),
                ],
                storedDTCs: [0x0401],
                permanentDTCs: [0x0401],
                freezeFrame: [0x02: [0x04, 0x01], 0x04: [0x80], 0x05: [0x7A], 0x0C: [0x0B, 0xB8], 0x0D: [0x00]],
                dids: [
                    0xF190: ascii(mondeoVIN),
                    0xF188: ascii("SIM1-14C204-AA"),
                    0xF111: ascii("SIM1-12A650-AA"),
                    0xF113: ascii("SIM1-12A650-AB"),
                    0xF124: ascii("SIM1-14C204-AB"),
                    0xF18C: ascii("SIM0042"),
                ],
                dtcs: [UDSDTC(code: DTCCode(raw: 0x0401), failureType: 0x00, status: DTCStatus(rawValue: 0xAF))],
                slowDIDs: [0xF113]
            ),
            VirtualECU(
                name: "ABS", request: 0x760, bus: .hsCAN,
                dids: [0xF190: ascii(mondeoVIN), 0xF111: ascii("SIM1-2C219-AA"), 0xF188: ascii("SIM1-2C219-BA")],
                dtcs: [UDSDTC(code: DTCCode(raw: 0xC100), failureType: 0x87, status: DTCStatus(rawValue: 0x28))]
            ),
            VirtualECU(
                name: "RCM", request: 0x737, bus: .hsCAN,
                dids: [0xF190: ascii(mondeoVIN), 0xF111: ascii("SIM1-14B321-AA")]
            ),
            VirtualECU(
                name: "IPC", request: 0x720, bus: .hsCAN,
                dids: [0xF190: ascii(mondeoVIN), 0xF111: ascii("SIM1-10849-AA")],
                dtcs: [UDSDTC(code: DTCCode(raw: 0x9318), failureType: 0x16, status: DTCStatus(rawValue: 0x08))]
            ),
            VirtualECU(
                name: "BCM", request: 0x726, bus: .msCAN,
                dids: [
                    0xF190: ascii(mondeoVIN), 0xF111: ascii("SIM1-14A067-AA"),
                    0xDE00: [0x2A, 0x2A, 0x80, 0x00, 0x29], 0xDE01: [0x00, 0x00, 0x0C, 0x40, 0x00],
                ]
            ),
            VirtualECU(name: "HVAC", request: 0x733, bus: .msCAN, dids: [0xF111: ascii("SIM1-18C612-AA")]),
            VirtualECU(
                name: "ACM", request: 0x727, bus: .msCAN,
                dids: [0xF111: ascii("SIM1-18C815-AA")],
                dtcs: [UDSDTC(code: DTCCode(raw: 0xC155), failureType: 0x87, status: DTCStatus(rawValue: 0x28))]
            ),
            VirtualECU(name: "DDM", request: 0x740, bus: .msCAN, dids: [0xF111: ascii("SIM1-14B533-AA")]),
        ]
    )
}
