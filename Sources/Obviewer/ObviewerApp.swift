import ObviewerMacApp
import SwiftUI

@main
struct ObviewerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1_180, minHeight: 760)
        }
        .defaultSize(width: 1_420, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Vault...") {
                    Task {
                        await model.chooseVault()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Reload Vault") {
                    Task {
                        await model.reloadVault()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.vaultURL == nil)
            }
        }
    }
}
