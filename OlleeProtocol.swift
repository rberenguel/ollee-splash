import Foundation
import CoreBluetooth

enum OlleeProtocol {
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let charUUID    = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

    /// Builds the BLE packet exactly like FreeOllee’s Android app.
    /// The value should be at most 6 characters; it is padded to 6 with spaces.
    static func buildPacket(value: String) -> Data {
        let text = String(value.prefix(6)).padding(toLength: 6, withPad: " ", startingAt: 0)
        let payload = Data([0x02, 0x2F]) + text.data(using: .ascii)!
        let crc = crc16(payload)
        let size = payload.count + 4

        var packet = Data()
        packet.append(0x00)
        packet.append(UInt8(size))
        packet.append(0xAA)
        packet.append(0x55)
        packet.append(UInt8((crc >> 8) & 0xFF))
        packet.append(UInt8(crc & 0xFF))
        packet.append(payload)
        return packet
    }

    private static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= (UInt16(byte) << 8)
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
                crc &= 0xFFFF
            }
        }
        return crc
    }
}
