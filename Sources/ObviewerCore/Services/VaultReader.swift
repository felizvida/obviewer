import Foundation

public struct VaultReader: VaultLoading, Sendable {
    private let supportedImages = Set(["png", "jpg", "jpeg", "gif", "webp", "heic"])
    private let supportedAudio = Set(["mp3", "m4a", "wav"])
    private let supportedVideo = Set(["mp4", "mov"])
    private let progressUpdateInterval = 25

    public init() {}

    public func loadVault(
        at rootURL: URL,
        progress: (@Sendable (VaultLoadingProgress) -> Void)? = nil
    ) throws -> VaultSnapshot {
        try reloadVault(at: rootURL, previousSnapshot: nil, changes: nil, progress: progress)
    }

    public func reloadVault(
        at rootURL: URL,
        previousSnapshot: VaultSnapshot?,
        changes: VaultReloadChanges?,
        progress: (@Sendable (VaultLoadingProgress) -> Void)? = nil
    ) throws -> VaultSnapshot {
        if let previousSnapshot, let changes {
            if changes.isEmpty {
                progress?(
                    VaultLoadingProgress(
                        processedFileCount: 0,
                        noteCount: previousSnapshot.notes.count,
                        attachmentCount: previousSnapshot.attachments.count,
                        currentPath: nil
                    )
                )
                return previousSnapshot
            }

            if changes.requiresFullReload == false {
                return try selectivelyReloadVault(
                    at: rootURL,
                    previousSnapshot: previousSnapshot,
                    changes: changes,
                    progress: progress
                )
            }
        }

        return try fullyReloadVault(at: rootURL, previousSnapshot: previousSnapshot, progress: progress)
    }

    private func fullyReloadVault(
        at rootURL: URL,
        previousSnapshot: VaultSnapshot?,
        progress: (@Sendable (VaultLoadingProgress) -> Void)?
    ) throws -> VaultSnapshot {
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
        var processedFileCount = 0
        let previousNotesByID = Dictionary(
            uniqueKeysWithValues: (previousSnapshot?.notes ?? []).map { ($0.id, $0) }
        )
        let previousAttachmentsByPath = Dictionary(
            uniqueKeysWithValues: (previousSnapshot?.attachments ?? []).map { ($0.relativePath, $0) }
        )

        func reportProgress(currentPath: String) {
            progress?(
                VaultLoadingProgress(
                    processedFileCount: processedFileCount,
                    noteCount: notes.count,
                    attachmentCount: attachments.count,
                    currentPath: currentPath
                )
            )
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }

            let relativePath = makeRelativePath(fileURL: fileURL, rootURL: rootURL)
            processedFileCount += 1
            if processedFileCount == 1 || processedFileCount.isMultiple(of: progressUpdateInterval) {
                reportProgress(currentPath: relativePath)
            }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let extensionName = fileURL.pathExtension.lowercased()

            if extensionName == "md" {
                let note: VaultNote
                if let previousNote = previousNotesByID[relativePath], previousNote.modifiedAt == modifiedAt {
                    note = previousNote
                } else {
                    note = try loadNote(
                        at: fileURL,
                        relativePath: relativePath,
                        modifiedAt: modifiedAt
                    )
                }
                notes.append(note)
                continue
            }

            guard let kind = classifyAttachment(extensionName) else { continue }
            let attachment: VaultAttachment
            if let previousAttachment = previousAttachmentsByPath[relativePath],
               previousAttachment.modifiedAt == modifiedAt,
               previousAttachment.kind == kind {
                attachment = previousAttachment
            } else {
                attachment = loadAttachment(
                    at: fileURL,
                    relativePath: relativePath,
                    kind: kind,
                    modifiedAt: modifiedAt
                )
            }

            attachments.append(attachment)
        }

        progress?(
            VaultLoadingProgress(
                processedFileCount: processedFileCount,
                noteCount: notes.count,
                attachmentCount: attachments.count,
                currentPath: nil
            )
        )

        return VaultSnapshot(rootURL: rootURL, notes: notes, attachments: attachments)
    }

    private func selectivelyReloadVault(
        at rootURL: URL,
        previousSnapshot: VaultSnapshot,
        changes: VaultReloadChanges,
        progress: (@Sendable (VaultLoadingProgress) -> Void)?
    ) throws -> VaultSnapshot {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
        ]

        var notesByPath = Dictionary(
            uniqueKeysWithValues: previousSnapshot.notes.map { ($0.relativePath, $0) }
        )
        var attachmentsByPath = Dictionary(
            uniqueKeysWithValues: previousSnapshot.attachments.map { ($0.relativePath, $0) }
        )
        let affectedPaths = changes.affectedPaths
        var processedFileCount = 0

        func reportProgress(currentPath: String?) {
            progress?(
                VaultLoadingProgress(
                    processedFileCount: processedFileCount,
                    noteCount: notesByPath.count,
                    attachmentCount: attachmentsByPath.count,
                    currentPath: currentPath
                )
            )
        }

        for relativePath in affectedPaths {
            processedFileCount += 1
            if processedFileCount == 1 || processedFileCount.isMultiple(of: progressUpdateInterval) {
                reportProgress(currentPath: relativePath)
            }

            if changes.removedPaths.contains(relativePath) {
                removeIndexedItem(
                    at: relativePath,
                    notesByPath: &notesByPath,
                    attachmentsByPath: &attachmentsByPath
                )
                continue
            }

            let fileURL = rootURL.appending(path: relativePath)
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                removeIndexedItem(
                    at: relativePath,
                    notesByPath: &notesByPath,
                    attachmentsByPath: &attachmentsByPath
                )
                continue
            }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            let extensionName = fileURL.pathExtension.lowercased()

            if extensionName == "md" {
                let note: VaultNote
                if let previousNote = notesByPath[relativePath], previousNote.modifiedAt == modifiedAt {
                    note = previousNote
                } else {
                    note = try loadNote(
                        at: fileURL,
                        relativePath: relativePath,
                        modifiedAt: modifiedAt
                    )
                }
                notesByPath[relativePath] = note
                attachmentsByPath.removeValue(forKey: relativePath)
                continue
            }

            if let kind = classifyAttachment(extensionName) {
                let attachment: VaultAttachment
                if let previousAttachment = attachmentsByPath[relativePath],
                   previousAttachment.modifiedAt == modifiedAt,
                   previousAttachment.kind == kind {
                    attachment = previousAttachment
                } else {
                    attachment = loadAttachment(
                        at: fileURL,
                        relativePath: relativePath,
                        kind: kind,
                        modifiedAt: modifiedAt
                    )
                }
                attachmentsByPath[relativePath] = attachment
                notesByPath.removeValue(forKey: relativePath)
            } else {
                removeIndexedItem(
                    at: relativePath,
                    notesByPath: &notesByPath,
                    attachmentsByPath: &attachmentsByPath
                )
            }
        }

        reportProgress(currentPath: nil)
        return VaultSnapshot(
            rootURL: rootURL,
            notes: Array(notesByPath.values),
            attachments: Array(attachmentsByPath.values)
        )
    }

    private func loadNote(
        at fileURL: URL,
        relativePath: String,
        modifiedAt: Date
    ) throws -> VaultNote {
        let markdown = try readText(at: fileURL)
        let fallbackTitle = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        let parsed = ObsidianParser().parse(markdown: markdown, fallbackTitle: fallbackTitle)
        return VaultNote(
            id: relativePath,
            title: parsed.title,
            relativePath: relativePath,
            folderPath: (relativePath as NSString).deletingLastPathComponent == "."
                ? ""
                : (relativePath as NSString).deletingLastPathComponent,
            previewText: parsed.previewText,
            frontmatter: parsed.frontmatter,
            tags: parsed.tags,
            outboundLinks: parsed.outboundLinks,
            tableOfContents: parsed.tableOfContents,
            blocks: parsed.blocks,
            wordCount: parsed.wordCount,
            readingTimeMinutes: parsed.readingTimeMinutes,
            modifiedAt: modifiedAt
        )
    }

    private func loadAttachment(
        at fileURL: URL,
        relativePath: String,
        kind: VaultAttachment.Kind,
        modifiedAt: Date
    ) -> VaultAttachment {
        VaultAttachment(
            relativePath: relativePath,
            url: fileURL,
            kind: kind,
            modifiedAt: modifiedAt
        )
    }

    private func removeIndexedItem(
        at relativePath: String,
        notesByPath: inout [String: VaultNote],
        attachmentsByPath: inout [String: VaultAttachment]
    ) {
        notesByPath.removeValue(forKey: relativePath)
        attachmentsByPath.removeValue(forKey: relativePath)
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
        let normalizedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = normalizedRoot.pathComponents
        let fileComponents = normalizedFile.pathComponents

        guard fileComponents.starts(with: rootComponents) else {
            return normalizedFile.lastPathComponent
        }

        let relativeComponents = fileComponents.dropFirst(rootComponents.count)
        return relativeComponents.joined(separator: "/")
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
