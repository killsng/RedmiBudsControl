import Foundation

/// MMA (Mi Mobile Accessory) protocol constants — reverse-engineered from
/// web1n/android_packages_apps_XiaomiTWS. See docs/PROTOCOL.md.
enum MMA {
    // MARK: SPP service UUIDs (classic Bluetooth RFCOMM)
    static let sppUUIDs: [String] = [
        "0000FD2D-0000-1000-8000-00805F9B34FB", // Xiaomi Fast Connect
        "00001101-0000-1000-8000-008584D01810"  // XiaoAI
    ]

    static let header: [UInt8] = [0xFE, 0xDC, 0xBA]
    static let footer: UInt8 = 0xEF

    // MARK: Opcodes
    enum Op: UInt8 {
        case getDeviceInfo = 0x02
        case setDeviceInfo = 0x08
        case setDeviceConfig = 0xF2
        case getDeviceConfig = 0xF3
        case notifyDeviceInfo = 0x0E
        case notifyDeviceConfig = 0xF4
        case sendAuth = 0x50
        case notifyAuth = 0x51
    }

    // MARK: GET_DEVICE_INFO field mask
    static let infoMaskBattery: UInt8 = 0x07

    // Notify device-info TLV type
    static let notifyTypeBattery: UInt8 = 0x00

    // MARK: Config IDs (2-byte, big-endian on the wire)
    enum Config: UInt16 {
        case buttonMode = 0x0002
        case multiConnect = 0x0004
        case equalizerMode = 0x0007
        case findEarbuds = 0x0009
        case noiseCancellationList = 0x000A
        case noiseCancellationMode = 0x000B
        case inEarMode = 0x000C
        case serialNumber = 0x0027
    }

    // MARK: Wire helpers

    /// Pack a config value for SET_DEVICE_CONFIG (0xF2):
    /// `[len][cfgIdHi][cfgIdLo][value...]`, len = value.count + 2.
    static func packSetConfig(_ id: UInt16, value: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.append(UInt8(value.count + 2))
        out.append(UInt8((id >> 8) & 0xFF))
        out.append(UInt8(id & 0xFF))
        out.append(contentsOf: value)
        return out
    }

    /// Pack a config id for GET_DEVICE_CONFIG (0xF3): `[cfgIdHi][cfgIdLo]`.
    static func packGetConfig(_ id: UInt16) -> [UInt8] {
        [UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF)]
    }

    /// Parse a config response/notify entry: `[len][cfgIdHi cfgIdLo][value...]`
    /// Returns (configId, value) or nil if malformed.
    static func parseConfigEntry(_ data: [UInt8], at offset: Int) -> (id: UInt16, value: [UInt8], next: Int)? {
        guard offset + 3 <= data.count else { return nil }
        let len = Int(data[offset])
        guard len >= 2, offset + 1 + len <= data.count else { return nil }
        let id = (UInt16(data[offset + 1]) << 8) | UInt16(data[offset + 2])
        let value = Array(data[(offset + 3)..<(offset + 1 + len)])
        return (id, value, offset + 1 + len)
    }

    /// Parse a device-info notify TLV (single-byte tag):
    /// repeated `[len][tag][value...]`.
    static func parseInfoTLV(_ data: [UInt8]) -> [(tag: UInt8, value: [UInt8])] {
        var result: [(UInt8, [UInt8])] = []
        var i = 0
        while i + 1 < data.count {
            let len = Int(data[i])
            guard len >= 1, i + 1 + len <= data.count else { break }
            let tag = data[i + 1]
            let value = Array(data[(i + 2)..<(i + 1 + len)])
            result.append((tag, value))
            i += 1 + len
        }
        return result
    }
}

// MARK: - Packet model

enum MMADirection { case request, response }

struct MMARawPacket {
    let direction: MMADirection
    let needReply: Bool
    let opcode: UInt8
    let opCodeSN: UInt8
    let status: UInt8          // response only
    let data: [UInt8]

    var isRequest: Bool { direction == .request }
}

// MARK: - Encoder

enum MMAEncoder {
    static func encode(request: MMARawPacket) -> [UInt8] {
        precondition(request.direction == .request)
        var frame: [UInt8] = MMA.header
        // type byte: bit7 = request(1); bit6 = needReply
        var typeByte: UInt8 = 0x80
        if request.needReply { typeByte |= 0x40 }
        frame.append(typeByte)
        frame.append(request.opcode)
        let paramLen = request.data.count + 1 // includes opCodeSN
        frame.append(UInt8((paramLen >> 8) & 0xFF))
        frame.append(UInt8(paramLen & 0xFF))
        frame.append(request.opCodeSN)
        frame.append(contentsOf: request.data)
        frame.append(MMA.footer)
        return frame
    }

    static func encode(response: MMARawPacket) -> [UInt8] {
        precondition(response.direction == .response)
        var frame: [UInt8] = MMA.header
        frame.append(0x00) // response, no needReply
        frame.append(response.opcode)
        let paramLen = response.data.count + 2 // status + opCodeSN
        frame.append(UInt8((paramLen >> 8) & 0xFF))
        frame.append(UInt8(paramLen & 0xFF))
        frame.append(response.status)
        frame.append(response.opCodeSN)
        frame.append(contentsOf: response.data)
        frame.append(MMA.footer)
        return frame
    }
}

// MARK: - Stream parser (accumulates bytes, emits complete frames)

final class MMAParser {
    private var buffer: [UInt8] = []

    /// Feed received bytes; returns zero or more complete packets.
    func feed(_ bytes: [UInt8]) -> [MMARawPacket] {
        buffer.append(contentsOf: bytes)
        var packets: [MMARawPacket] = []

        while let packet = tryTakePacket() {
            packets.append(packet)
        }
        return packets
    }

    private func tryTakePacket() -> MMARawPacket? {
        // Locate header FE DC BA.
        var start = 0
        while true {
            if start + 3 > buffer.count {
                // Keep up to 2 trailing bytes in case of a partial header.
                if start >= 1 { buffer = Array(buffer[(start - 1)...]) } else { buffer = [] }
                return nil
            }
            if buffer[start] == 0xFE && buffer[start + 1] == 0xDC && buffer[start + 2] == 0xBA {
                break
            }
            start += 1
        }
        if start > 0 { buffer = Array(buffer[start...]) }

        // Need header(3) + type(1) + opcode(1) + len(2) = 8 bytes.
        guard buffer.count >= 8 else { return nil }
        let typeByte = buffer[3]
        let opcode = buffer[4]
        let paramLen = (Int(buffer[5]) << 8) | Int(buffer[6])
        let total = 7 + paramLen + 1 // + footer
        guard buffer.count >= total else { return nil }

        // Validate footer.
        guard buffer[total - 1] == MMA.footer else {
            // Not a real frame; drop the header byte and resync.
            buffer = Array(buffer[1...])
            return nil
        }

        let isRequest = (typeByte & 0x80) != 0
        let needReply = (typeByte & 0x40) != 0
        let opCodeSN: UInt8
        let status: UInt8
        let payload: [UInt8]

        if isRequest {
            opCodeSN = buffer[7]
            status = 0
            payload = Array(buffer[8..<(7 + paramLen)])
        } else {
            status = buffer[7]
            opCodeSN = buffer[8]
            payload = Array(buffer[9..<(7 + paramLen)])
        }

        let packet = MMARawPacket(
            direction: isRequest ? .request : .response,
            needReply: needReply,
            opcode: opcode,
            opCodeSN: opCodeSN,
            status: status,
            data: payload
        )

        buffer = Array(buffer[total...])
        return packet
    }
}
