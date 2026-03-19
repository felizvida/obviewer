import Foundation

public struct VaultReader: VaultLoading, Sendable {
    private let supportedImages = Set(["png", "jpg", "jpeg", "gif", "webp", "heic"])
    private let supportedAudio = Set(["mp3", "m4a", "wav"])
    private let supportedVideo = Set(["mp4", "mov"])

    public init() {}

    public func loadVault(at rootURL: URL) throws -> VaultSnapshot {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .nameKey,
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw VaultReaderError.unreadableVault(rootURL.path)
        }

        var notes = [VaultNote]()
        var attachments = [VaultAttachment]()

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }

            let relativePath = makeRelativePath(fileURL: fileURL, rootURL: rootURL)
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let extensionName = fileURL.pathExtension.lowercased()

            if extensionName == "md" {
                let markdown = try readText(at: fileURL)
                let fallbackTitle = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
                let parsed = ObsidianParser().parse(markdown: markdown, fallbackTitle: fallbackTitle)
                let note = VaultNote(
                    id: relativePath,
                    title: parsed.title,
                    relativePath: relativePath,
                    folderPath: (relativePath as NSString).deletingLastPathComponent == "."
                        ? ""
                        : (relativePath as NSString).deletingLastPathComponent,
                    previewText: parsed.previewText,
                    tags: parsed.tags,
                    outboundLinks: parsed.outboundLinks,
                    tableOfContents: parsed.tableOfContents,
                    blocks: parsed.blocks,
                    wordCount: parsed.wordCount,
                    readingTimeMinutes: parsed.readingTimeMinutes,
                    modifiedAt: modifiedAt
                )
                notes.append(note)
                continue
            }

            guard let kind = classifyAttachment(extensionName) else { continue }
            let attachment = VaultAttachment(
                relativePath: relativePath,
                url: fileURL,
                kind: kind
            )

            attachments.append(attachment)
        }

        return VaultSnapshot(rootURL: rootURL, notes: notes, attachments: attachments)
    }

    private func readText(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let data = try handle.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func classifyAttachment(_ extensionName: String) -> VaultAttachment.Kind? {
        if supportedImages.contains(extensionName) {
            return .image
        }
        if extensionName == "pdf" {
            return .pdf
        }
        if supportedAudio.contains(extensionName) {
            return .audio
        }
        if supportedVideo.contains(extensionName) {
            return .video
        }
        return .other
    }

    private func makeRelativePath(fileURL: URL, rootURL: URL) -> String {
        fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
    }
}

public enum VaultReaderError: LocalizedError {
    case unreadableVault(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableVault(let path):
            return "Unable to read vault at \(path)."
        }
    }
}
