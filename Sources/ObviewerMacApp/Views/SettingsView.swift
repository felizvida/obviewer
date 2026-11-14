import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// App settings: reading, editing handoff, and Finder integration.
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            ReadingSettings()
                .tabItem { Label("Reading", systemImage: "textformat.size") }
            EditingSettings()
                .tabItem { Label("Editing", systemImage: "square.and.pencil") }
            FinderSettings()
                .tabItem { Label("Finder", systemImage: "folder") }
        }
        .frame(width: 520)
        .padding(20)
        .tint(VisualTheme.accent)
    }
}

@MainActor
private struct ReadingSettings: View {
    @AppStorage(ReaderPreferenceKeys.theme) private var theme = "system"
    @AppStorage(ReaderPreferenceKeys.textScale) private var textScale = 1.0
    @AppStorage(ReaderPreferenceKeys.measure) private var measure = ReaderMeasure.standard

    var body: some View {
        Form {
            Picker("Appearance", selection: $theme) {
                Text("Match System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .onChange(of: theme) { applyAppAppearance() }

            LabeledContent("Text size") {
                HStack {
                    Slider(value: $textScale, in: ReaderTextSize.minimum...ReaderTextSize.maximum, step: ReaderTextSize.step)
                    Text("\(Int((textScale * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            LabeledContent("Line length") {
                HStack {
                    Slider(
                        value: Binding(get: { Double(measure) }, set: { measure = Int($0) }),
                        in: Double(ReaderMeasure.minimum)...Double(ReaderMeasure.maximum),
                        step: 2
                    )
                    Text("\(measure) ch")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { applyAppAppearance() }
    }

    private func applyAppAppearance() {
        AppAppearance.apply(theme)
    }
}

private struct EditingSettings: View {
    @ObservedObject private var handoff = EditorHandoff.shared

    var body: some View {
        Form {
            Picker("Edit notes in", selection: Binding(
                get: { handoff.preferredEditorID },
                set: { handoff.preferredEditorID = $0 }
            )) {
                Text("Automatic").tag(EditorHandoff.automaticID)
                Divider()
                ForEach(handoff.installedEditors) { editor in
                    Text(editor.name).tag(editor.bundleID)
                }
                if isCustom {
                    Text(handoff.displayName(for: handoff.preferredEditorID)).tag(handoff.preferredEditorID)
                }
            }
            Button("Choose Another App…") { handoff.chooseCustomEditor() }

            Text("Automatic opens notes in Sublime Text, a light and fast editor. Without Sublime Text, it uses the file's default app (never a heavy IDE like Spyder), then CotEditor, BBEdit, or TextEdit. Pick Obsidian here to open vault notes in Obsidian. Obviewer never edits files itself. It reloads the note each time you save in your editor.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var isCustom: Bool {
        let id = handoff.preferredEditorID
        return id != EditorHandoff.automaticID && handoff.installedEditors.contains(where: { $0.bundleID == id }) == false
    }
}

@MainActor
private struct FinderSettings: View {
    @State private var status: String?

    var body: some View {
        Form {
            LabeledContent("Default app") {
                Button("Make Obviewer the Default for Markdown") { makeDefault() }
            }
            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("You can also select any .md file in Finder, choose File › Get Info, pick Obviewer under “Open with”, and click Change All.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Quick Look") {
                Text("Select a Markdown file in Finder and press Space.")
                    .foregroundStyle(.secondary)
            }
            Text("If the preview shows plain text, open Obviewer once, then turn on its extension in System Settings › General › Login Items & Extensions › Quick Look.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func makeDefault() {
        let types = [UTType("net.daringfireball.markdown"), UTType(filenameExtension: "md")].compactMap { $0 }
        let appURL = Bundle.main.bundleURL
        Task {
            var failures = [String]()
            for type in Set(types) {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
            let message = failures.isEmpty
                ? "Markdown files now open in Obviewer."
                : "macOS didn't allow the change (\(failures.first ?? "")). Use Get Info › Open with › Change All instead."
            await MainActor.run {
                status = message
            }
        }
    }
}

/// Applies the chosen appearance to the whole app (the web reader follows it automatically).
public enum AppAppearance {
    @MainActor
    public static func applySaved() {
        apply(UserDefaults.standard.string(forKey: ReaderPreferenceKeys.theme) ?? "system")
    }

    @MainActor
    public static func apply(_ theme: String) {
        switch theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
