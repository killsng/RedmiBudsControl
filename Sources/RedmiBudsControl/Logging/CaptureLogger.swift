import Foundation
import Combine

/// In-memory + on-disk packet capture. Every BLE event (scan, services,
/// characteristics, notify values, our writes) is published to the UI and
/// appended to a timestamped .log file under ~/Documents/RedmiBudsControl/captures.
/// That file is what we hand off in Phase 2 to decode the Xiaomi protocol.
/// Not @MainActor: CoreBluetooth callbacks arrive on the main queue
/// (queue: .main), so @Published updates happen on the main thread at runtime.
final class CaptureLogger: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 1500
    private let fileHandle: FileHandle?
    let fileURL: URL?

    init() {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/RedmiBudsControl/captures", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .filter { $0.isNumber }
        let url = dir.appendingPathComponent("capture_\(stamp).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)

        self.fileURL = url
        self.fileHandle = try? FileHandle(forWritingTo: url)
        writeRaw("# Redmi Buds Control capture started \(Date())")
    }

    func log(_ direction: LogEntry.Direction, _ message: String, data: Data? = nil) {
        let entry = LogEntry(direction: direction, message: message, data: data)
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        writeRaw(entry.formatted)
    }

    func info(_ m: String) { log(.info, m) }
    func tx(_ m: String, _ d: Data? = nil) { log(.tx, m, data: d) }
    func rx(_ m: String, _ d: Data? = nil) { log(.rx, m, data: d) }
    func warn(_ m: String) { log(.warn, m) }
    func error(_ m: String) { log(.error, m) }

    func clear() { entries.removeAll() }

    var capturePath: String? { fileURL?.path }

    private func writeRaw(_ line: String) {
        guard let fh = fileHandle, let bytes = (line + "\n").data(using: .utf8) else { return }
        try? fh.write(contentsOf: bytes)
        try? fh.synchronize()
    }
}
