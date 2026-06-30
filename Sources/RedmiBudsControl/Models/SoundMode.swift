import Foundation

/// EQ presets. `rawValue` IS the MMA wire byte (config 0x0007).
/// Source: web1n EarbudsConstants.
enum SoundMode: UInt8, CaseIterable, Identifiable {
    case original = 0x00
    case vocal = 0x01
    case bass = 0x05
    case treble = 0x06
    case volumeBoost = 0x07

    var id: UInt8 { rawValue }
    var wireByte: UInt8 { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .vocal: return "Vocal"
        case .bass: return "Bass"
        case .treble: return "Treble"
        case .volumeBoost: return "Volume"
        }
    }
}
