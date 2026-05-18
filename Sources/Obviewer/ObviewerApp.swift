import ObviewerMacApp
import SwiftUI

@main
struct ObviewerApp: App {
    @StateObject private var model = AppModel()
    private let launchInputRequest: LaunchReadingInputRequest?

    init() {
        launchInputRequest = LaunchReadingInputParser.parse(Array(CommandLine.arguments.dropFirst()))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1_180, minHeight: 760)
                .task {
                    await model.openLaunchInputOrRestore(launchInputRequest)
                }
                .onOpenURL { url in
                    Task {
                        await model.open(url, preferredProfile: nil, persistBookmark: true)
                    }
                }
        }
        .defaultSize(width: 1_420, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open File or Folder...") {
                    Task {
                        await model.chooseVault()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Reload") {
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
