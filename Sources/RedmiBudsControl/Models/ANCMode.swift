import Foundation

/// Noise-control modes. `rawValue` IS the MMA wire byte (config 0x000B).
/// Source: web1n EarbudsConstants (off=0x00, ANC=0x01, transparency=0x02).
enum ANCMode: UInt8, CaseIterable, Identifiable {
    case off = 0x00
    case noiseCanceling = 0x01
    case transparency = 0x02

    var id: UInt8 { rawValue }
    var wireByte: UInt8 { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .noiseCanceling: return "ANC"
        case .transparency: return "Transparency"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "speaker.wave.1"
        case .noiseCanceling: return "ear.fill"
        case .transparency: return "ear"
        }
    }
}
