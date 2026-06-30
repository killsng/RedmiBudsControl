import SwiftUI

struct LogView: View {
    @ObservedObject var manager: EarbudsManager
    @State private var filter = ""

    private var filtered: [LogEntry] {
        manager.logger.entries.filter {
            filter.isEmpty || $0.formatted.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            List {
                ForEach(filtered.reversed()) { entry in
                    Text(entry.formatted)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(color(for: entry))
                        .textSelection(.enabled)
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 680, minHeight: 420)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
            Text("Live packet capture").font(.headline)
            Spacer()
            TextField("Filter…", text: $filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("Reveal file") {
                if let path = manager.logger.capturePath {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Button("Clear") { manager.logger.clear() }
        }
        .padding(10)
    }

    private func color(for entry: LogEntry) -> Color {
        switch entry.direction {
        case .error: return .red
        case .warn: return .orange
        case .tx: return .blue
        case .rx: return .primary
        case .info: return .secondary
        }
    }
}
