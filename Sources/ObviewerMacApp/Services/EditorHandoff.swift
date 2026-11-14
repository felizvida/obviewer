import AppKit
import Foundation
import UniformTypeIdentifiers

/// "Edit in…": hands the file to another app. Obviewer itself stays read-only;
/// the live-reload watcher picks up saves made in that app.
@MainActor
final class EditorHandoff: ObservableObject {
    static let shared = EditorHandoff()

    struct Editor: Identifiable, Hashable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    static let automaticID = "automatic"
    static let obsidianBundleID = "md.obsidian"

    /// The maintainer's choice: a light, fast editor is the default handoff.
    static let sublimeTextBundleIDs = ["com.sublimetext.4", "com.sublimetext.3"]

    /// Apps never picked automatically, even if macOS lists them as the default
    /// for .md files (heavy IDEs that take ages to open a note).
    static let neverAutomatic = ["org.spyder-ide", "spyder"]

    /// Well-known Markdown-capable editors, shown when installed. Light editors first.
    static let knownEditors: [Editor] = [
        Editor(bundleID: "com.sublimetext.4", name: "Sublime Text"),
        Editor(bundleID: "com.sublimetext.3", name: "Sublime Text 3"),
        Editor(bundleID: "com.coteditor.CotEditor", name: "CotEditor"),
        Editor(bundleID: "com.barebones.bbedit", name: "BBEdit"),
        Editor(bundleID: obsidianBundleID, name: "Obsidian"),
        Editor(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        Editor(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        Editor(bundleID: "dev.zed.Zed", name: "Zed"),
        Editor(bundleID: "abnerworks.Typora", name: "Typora"),
        Editor(bundleID: "pro.writer.mac", name: "iA Writer"),
        Editor(bundleID: "com.marktext.app", name: "MarkText"),
        Editor(bundleID: "com.apple.TextEdit", name: "TextEdit"),
    ]

    private let defaultsKey = "obviewer.editor.bundleID"

    var preferredEditorID: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? Self.automaticID }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    var installedEditors: [Editor] {
        Self.knownEditors.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    func displayName(for bundleID: String) -> String {
        if bundleID == Self.automaticID { return "Automatic" }
        if let known = Self.knownEditors.first(where: { $0.bundleID == bundleID }) { return known.name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    /// Lets the user pick any app as their editor.
    func chooseCustomEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Use This Editor"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        preferredEditorID = bundleID
    }

    func open(fileURL: URL, preferObsidian: Bool, onError: @escaping (String) -> Void) {
        let editorID = preferredEditorID

        // Obsidian only when chosen explicitly; Automatic prefers a light editor.
        if editorID == Self.obsidianBundleID {
            if openInObsidian(fileURL) { return }
        }

        let appURL: URL?
        if editorID != Self.automaticID, editorID != Self.obsidianBundleID {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editorID)
        } else {
            appURL = defaultEditorURL(for: fileURL)
        }

        guard let appURL else {
            onError("No editor is set. Choose one in Settings › Editing.")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in onError("Couldn’t open the editor: \(error.localizedDescription)") }
            }
        }
    }

    private func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// obsidian://open?path=… opens the note in whichever vault contains it.
    private func openInObsidian(_ fileURL: URL) -> Bool {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: fileURL.path)]
        guard let url = components.url else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Automatic: Sublime Text if installed; otherwise the system default for the
    /// file unless that's Obviewer or a heavy IDE (Spyder); otherwise the first
    /// installed light editor, ending with TextEdit.
    private func defaultEditorURL(for fileURL: URL) -> URL? {
        for bundleID in Self.sublimeTextBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(toOpen: fileURL), Self.isAcceptableAutomaticEditor(url) {
            return url
        }
        for editor in Self.knownEditors where editor.bundleID != Self.obsidianBundleID {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleID) {
                return url
            }
        }
        return nil
    }

    static func isAcceptableAutomaticEditor(_ appURL: URL) -> Bool {
        let bundleID = (Bundle(url: appURL)?.bundleIdentifier ?? "").lowercased()
        if bundleID == Bundle.main.bundleIdentifier?.lowercased() { return false }
        let name = appURL.deletingPathExtension().lastPathComponent.lowercased()
        return neverAutomatic.contains { bundleID.hasPrefix($0) || name.contains($0) } == false
    }
}
