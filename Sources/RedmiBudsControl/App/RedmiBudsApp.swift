import SwiftUI

@main
struct RedmiBudsApp: App {
    @StateObject private var manager = EarbudsManager()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(manager: manager)
                .onAppear { manager.refreshPaired() }
        } label: {
            Image(nsImage: menuIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Packet Log — Redmi Buds", id: "packet-log") {
            LogView(manager: manager)
        }
        .defaultSize(width: 760, height: 480)

        Settings {
            SettingsView(manager: manager)
        }
    }

    private var statusSymbol: String {
        manager.protocolReady ? "airpodspro.fill" : "airpodspro"
    }

    private var menuIcon: NSImage {
        let img = NSImage(systemSymbolName: statusSymbol,
                          accessibilityDescription: manager.protocolReady ? "Connected" : "Offline")
        img?.isTemplate = true   // correct menu-bar tinting (no transparent/black-oval bug)
        return img ?? NSImage()
    }
}
