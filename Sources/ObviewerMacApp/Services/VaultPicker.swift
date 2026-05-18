import AppKit
import Foundation
import UniformTypeIdentifiers

protocol VaultChoosing {
    @MainActor
    func chooseVault() -> URL?
}

struct VaultPicker: VaultChoosing {
    @MainActor
    func chooseVault() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, UTType(filenameExtension: "md") ?? .plainText]
        panel.prompt = "Open"
        panel.message = "Choose an existing Obsidian vault, Markdown folder, or .md file. Obviewer stores read-only security-scoped access and never writes to the source."

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.urls.first
    }
}
