import SwiftUI
import AppKit

struct MenuContent: View {
    @ObservedObject var manager: EarbudsManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if manager.linkState == .connected || manager.linkState == .authed {
                DeviceControls(manager: manager)
            } else {
                DevicePicker(manager: manager)
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "airpodspro")
                .font(.title3)
                .foregroundStyle(manager.protocolReady ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Redmi Buds Control").font(.headline)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var subtitle: String {
        switch manager.linkState {
        case .idle: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected — negotiating"
        case .authed: return "Connected & authenticated"
        case .failed: return "Connection failed (see log)"
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass").font(.caption)
            Text("Live capture: ~/Documents/RedmiBudsControl/captures")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Settings") { openSettings() }
                .buttonStyle(.borderless).font(.caption)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
        }
    }
}
