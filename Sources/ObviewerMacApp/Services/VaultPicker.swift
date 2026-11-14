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
        let noteTypes = ["md", "markdown", "mdown", "mkd", "txt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = [.folder] + noteTypes
        panel.prompt = "Open"
        panel.message = "Choose an Obsidian vault, a Markdown or DokuWiki folder, or a single note file. Obviewer stores read-only security-scoped access and never writes to the source."

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.urls.first
    }
}
