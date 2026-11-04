import SwiftUI

/// Holds the app model without `@State`, which needs the SwiftUI macro plugin
/// that Command Line Tools do not ship.
@MainActor
enum DeskStore {
    static let model = AppModel()
}

@main
struct PersonifyDeskApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(DeskStore.model)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button(DeskStore.model.scanning ? "Stop Scan" : "Scan") {
                    DeskStore.model.toggleScan()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(DeskStore.model)
        }
    }
}
