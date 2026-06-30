import SwiftUI

struct DevicePicker: View {
    @ObservedObject var manager: EarbudsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Paired buds").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    manager.refreshPaired()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
            }

            if manager.linkState == .connecting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Opening RFCOMM channel…").font(.caption)
                }
            } else if manager.linkState == .failed {
                Text("Connection failed — check the packet log for details.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if manager.paired.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Redmi/Xiaomi buds found among paired devices.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Pair your buds in System Settings › Bluetooth first, then tap Refresh.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(manager.paired) { d in
                    Button {
                        manager.connect(d)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.name).font(.callout)
                                Text(d.address).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "link").foregroundStyle(Color.accentColor)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
