import SwiftUI

struct DeviceControls: View {
    @ObservedObject var manager: EarbudsManager
    @Environment(\.openWindow) private var openWindow

    private var deviceName: String {
        manager.paired.first { $0.address == manager.selectedAddress }?.name ?? "Earbuds"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(deviceName).bold()
                Spacer()
                Label(stateLabel, systemImage: stateIcon)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(stateColor)
            }

            batteryRow

            Divider()

            Text("Noise control").font(.caption).foregroundStyle(.secondary)
            Picker("ANC", selection: ancBinding) {
                ForEach(ANCMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!manager.protocolReady)

            Text("Equalizer").font(.caption).foregroundStyle(.secondary)
            Picker("EQ", selection: eqBinding) {
                ForEach(SoundMode.allCases) { Text($0.label).tag($0) }
            }
            .disabled(!manager.protocolReady)

            if manager.authRequired && !manager.authed {
                Label {
                    Text("Auth required for writes — crypto not yet implemented (see log).")
                        .font(.caption2).foregroundStyle(.orange)
                } icon: { Image(systemName: "exclamationmark.triangle.fill").font(.caption2) }
            } else if !manager.protocolReady {
                Label {
                    Text("Negotiating with earbuds…").font(.caption2).foregroundStyle(.secondary)
                } icon: { ProgressView().controlSize(.mini) }
            }

            HStack {
                Button("Packet log") { openWindow(id: "packet-log") }
                Spacer()
                Button("Disconnect", role: .destructive) { manager.disconnect() }
            }
        }
    }

    // Bindings that send a command on change.
    private var ancBinding: Binding<ANCMode> {
        Binding(get: { manager.ancMode }, set: { manager.setANC($0) })
    }
    private var eqBinding: Binding<SoundMode> {
        Binding(get: { manager.soundMode }, set: { manager.setEQ($0) })
    }

    private var batteryRow: some View {
        HStack(spacing: 14) {
            BatteryPill(label: "L", pct: manager.battery.leftPct, charging: manager.battery.leftCharging)
            BatteryPill(label: "R", pct: manager.battery.rightPct, charging: manager.battery.rightCharging)
            BatteryPill(label: "Case", pct: manager.battery.casePct, charging: manager.battery.caseCharging)
        }
    }

    private var stateLabel: String {
        manager.authed ? "Authenticated" : (manager.protocolReady ? "Ready" : "Connected")
    }
    private var stateIcon: String {
        manager.protocolReady ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
    }
    private var stateColor: Color {
        manager.protocolReady ? .green : .secondary
    }
}

private struct BatteryPill: View {
    let label: String
    let pct: Int?
    let charging: Bool

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Image(systemName: charging ? "bolt.fill" : batteryIcon)
                    .font(.caption2)
                    .foregroundStyle(color)
            }
            Text(pct.map { "\($0)%" } ?? "—")
                .font(.callout.monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var batteryIcon: String {
        guard let pct else { return "battery.0" }
        switch pct {
        case 80...: return "battery.100"
        case 60...: return "battery.75"
        case 40...: return "battery.50"
        case 20...: return "battery.25"
        default: return "battery.0"
        }
    }

    private var color: Color {
        guard let pct else { return .secondary }
        return pct <= 15 ? .red : .primary
    }
}
