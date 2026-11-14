import ObviewerMacApp
import SwiftUI

@main
struct ObviewerApp: App {
    @NSApplicationDelegateAdaptor(ObviewerAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    private let launchInputRequest: LaunchReadingInputRequest?

    init() {
        launchInputRequest = LaunchReadingInputParser.parse(Array(CommandLine.arguments.dropFirst()))
    }

    var body: some Scene {
        // One library window: it owns the app-wide model and its web reader.
        Window("Obviewer", id: SceneID.library) {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    AppAppearance.applySaved()
                    await model.openLaunchInputOrRestore(launchInputRequest)
                }
        }
        .defaultSize(width: 1_380, height: 900)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
        .commands {
            ObviewerCommands()
        }

        // One window per note file opened from Finder.
        WindowGroup("Note", id: SceneID.note, for: NoteWindowRequest.self) { $request in
            NoteWindowView(request: request)
        }
        .defaultSize(width: 860, height: 980)
        .handlesExternalEvents(matching: [])

        Settings {
            SettingsView()
        }
    }
}
