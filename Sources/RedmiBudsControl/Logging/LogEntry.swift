import Foundation

struct LogEntry: Identifiable, Hashable {
    enum Direction: String { case tx, rx, info, warn, error }

    let id = UUID()
    let date = Date()
    let direction: Direction
    let message: String
    let data: Data?

    var formatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        var line = "\(f.string(from: date)) [\(direction.rawValue.uppercased())] \(message)"
        if let data { line += "  hex=" + data.hexLine }
        return line
    }
}

extension Data {
    var hexLine: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
