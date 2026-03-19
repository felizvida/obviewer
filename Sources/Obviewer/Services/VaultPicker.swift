import AppKit
import Foundation

struct VaultPicker {
    @MainActor
    func chooseVault() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.message = "Choose an Obsidian vault folder. Obviewer only requests read-only access."

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.urls.first
    }
}
