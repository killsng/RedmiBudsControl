import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var manager: EarbudsManager
    @State private var launchAtLogin = false
    @State private var statusMsg = ""

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in toggleLogin(on) }
            }
            Section("Device") {
                Button("Refresh battery / ANC / EQ") { manager.refreshAll() }
                if !manager.protocolReady {
                    Text("Not connected to earbuds.").foregroundStyle(.secondary)
                }
            }
            Section("Diagnostics") {
                if let path = manager.logger.capturePath {
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
            }
            if !statusMsg.isEmpty {
                Text(statusMsg).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(10)
        .frame(minWidth: 420, minHeight: 240)
        .onAppear { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
    }

    private func toggleLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            statusMsg = on ? "Added to login items." : "Removed from login items."
        } catch {
            statusMsg = "Failed: \(error.localizedDescription)"
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
