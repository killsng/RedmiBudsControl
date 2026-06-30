import Foundation

/// Auth handshake for the MMA channel.
///
/// `encrypt(16 bytes) -> 16 bytes` is implemented in Xiaomi's closed native lib
/// `libxm_bluetooth.so`. macOS blocks executing that ARM code directly (no JIT
/// without a signing identity), so we run it through a bundled Unicorn emulator
/// (pure-software ARM interpretation — no mmap-exec, works everywhere).
///
/// The emulator (`resources/auth_oracle.py` + `resources/libxm_bluetooth.so`)
/// is bit-exact, validated against the real Redmi Buds 6 Pro
/// (encrypt(0…0) = bca5905bc849392e7bf9fdcdc570ef77, device-confirmed).
enum AuthHandler {

    static func encryptAuthCheckData(_ random: [UInt8]) -> [UInt8] {
        guard let helper = Bundle.main.url(forResource: "auth_helper", withExtension: nil),
              let so = Bundle.main.url(forResource: "libxm_bluetooth", withExtension: "so") else {
            return random // bundled oracle missing — auth will fail
        }
        let hex = random.map { String(format: "%02x", $0) }.joined()
        let proc = Process()
        proc.executableURL = helper
        proc.arguments = [hex, so.path]
        let out = Pipe(); proc.standardOutput = out; proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return random
        }
        let raw = out.fileHandleForReading.readDataToEndOfFile()
        let s = (String(data: raw, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 32 else { return random }
        var bytes = [UInt8](); bytes.reserveCapacity(16)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            if let b = UInt8(s[idx..<next], radix: 16) { bytes.append(b) }
            idx = next
        }
        return bytes.count == 16 ? bytes : random
    }

    static func randomAuthCheckData() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return bytes
    }
}
