import Foundation

public enum ReadingProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case markdown
    case obsidian
    case dokuwiki

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .obsidian:
            return "Obsidian"
        case .dokuwiki:
            return "DokuWiki"
        }
    }
}

public enum ReadingInputKind: String, Codable, Sendable {
    case folder
    /// A single note file (Markdown, or a DokuWiki .txt page).
    case markdownFile
}

/// Where DokuWiki keeps pages and media, relative to the opened folder.
public struct DokuWikiLayout: Equatable, Sendable {
    public let pagesBase: String
    public let mediaBase: String

    public init(pagesBase: String, mediaBase: String) {
        self.pagesBase = pagesBase
        self.mediaBase = mediaBase
    }

    /// Detects the layout for a folder the user opened: the DokuWiki install
    /// root (`data/pages`), the `data` folder (`pages`), or `pages` itself.
    public static func detect(in folderURL: URL, fileManager: FileManager = .default) -> DokuWikiLayout? {
        func isDirectory(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        if isDirectory(folderURL.appendingPathComponent("data/pages")) {
            return DokuWikiLayout(pagesBase: "data/pages", mediaBase: "data/media")
        }
        if isDirectory(folderURL.appendingPathComponent("pages")),
           isDirectory(folderURL.appendingPathComponent("media"))
            || isDirectory(folderURL.appendingPathComponent("meta"))
            || isDirectory(folderURL.appendingPathComponent("attic")) {
            return DokuWikiLayout(pagesBase: "pages", mediaBase: "media")
        }
        if folderURL.lastPathComponent == "pages", folderURL.deletingLastPathComponent().lastPathComponent == "data" {
            return DokuWikiLayout(pagesBase: "", mediaBase: "")
        }
        return nil
    }

    /// For a single `.txt` page inside `.../data/pages/...`, the layout relative to the page's folder is unknown
    /// (and outside the sandbox grant), so media can't be resolved; links still render.
    public static func isInsidePagesTree(_ fileURL: URL) -> Bool {
        let components = fileURL.standardizedFileURL.pathComponents
        guard let pagesIndex = components.lastIndex(of: "pages"), pagesIndex > 0 else { return false }
        return components[pagesIndex - 1] == "data"
    }
}

public struct ReadingInputSource: Equatable, Sendable {
    public let url: URL
    public let kind: ReadingInputKind
    public let profile: ReadingProfile
    /// Note to select after loading a folder (vault-relative path).
    public let preferredFocusPath: String?

    public init(url: URL, kind: ReadingInputKind, profile: ReadingProfile, preferredFocusPath: String? = nil) {
        self.url = url.standardizedFileURL
        self.kind = kind
        self.profile = profile
        self.preferredFocusPath = preferredFocusPath
    }

    public var rootURL: URL {
        switch kind {
        case .folder:
            return url
        case .markdownFile:
            return url.deletingLastPathComponent()
        }
    }

    public var watchURL: URL? {
        switch kind {
        case .folder:
            return rootURL
        case .markdownFile:
            return nil
        }
    }

    /// The single file to watch when `kind == .markdownFile`.
    public var watchedFileURL: URL? {
        kind == .markdownFile ? url : nil
    }

    public var focusRelativePath: String? {
        switch kind {
        case .folder:
            return preferredFocusPath
        case .markdownFile:
            return url.lastPathComponent
        }
    }

    public var dokuWikiLayout: DokuWikiLayout? {
        guard profile == .dokuwiki else { return nil }
        switch kind {
        case .folder:
            return DokuWikiLayout.detect(in: url) ?? DokuWikiLayout(pagesBase: "", mediaBase: "")
        case .markdownFile:
            return DokuWikiLayout(pagesBase: "", mediaBase: "")
        }
    }

    /// The same source read with a different profile (the flavor badge override).
    public func with(profile: ReadingProfile) -> ReadingInputSource {
        ReadingInputSource(url: url, kind: kind, profile: profile, preferredFocusPath: preferredFocusPath)
    }

    public func with(focus relativePath: String?) -> ReadingInputSource {
        ReadingInputSource(url: url, kind: kind, profile: profile, preferredFocusPath: relativePath)
    }
}

public enum NoteFileTypes {
    /// Extensions opened as Markdown notes.
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]
    /// Extensions opened as DokuWiki pages.
    public static let dokuWikiExtensions: Set<String> = ["txt"]

    public static func isNoteFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return markdownExtensions.contains(ext) || dokuWikiExtensions.contains(ext)
    }

    public static func noteExtensions(for profile: ReadingProfile) -> Set<String> {
        profile == .dokuwiki ? dokuWikiExtensions : markdownExtensions
    }
}

public protocol ReadingInputAdapting: Sendable {
    func makeInputSource(for url: URL, preferredProfile: ReadingProfile?) -> ReadingInputSource
}

public struct DefaultReadingInputAdapter: ReadingInputAdapting {
    public init() {}

    public func makeInputSource(for url: URL, preferredProfile: ReadingProfile? = nil) -> ReadingInputSource {
        let standardizedURL = url.standardizedFileURL
        let ext = standardizedURL.pathExtension.lowercased()
        if isDirectory(standardizedURL) == false {
            if NoteFileTypes.markdownExtensions.contains(ext) {
                return ReadingInputSource(url: standardizedURL, kind: .markdownFile, profile: preferredProfile ?? .markdown)
            }
            if NoteFileTypes.dokuWikiExtensions.contains(ext) {
                let detected: ReadingProfile = DokuWikiLayout.isInsidePagesTree(standardizedURL) ? .dokuwiki : .markdown
                return ReadingInputSource(url: standardizedURL, kind: .markdownFile, profile: preferredProfile ?? detected)
            }
        }

        return ReadingInputSource(
            url: standardizedURL,
            kind: .folder,
            profile: preferredProfile ?? detectedFolderProfile(for: standardizedURL)
        )
    }

    public func detectedFolderProfile(for url: URL) -> ReadingProfile {
        let obsidianDirectory = url.appending(path: ".obsidian", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: obsidianDirectory.path) {
            return .obsidian
        }
        if DokuWikiLayout.detect(in: url) != nil {
            return .dokuwiki
        }
        return .markdown
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

public protocol ReadingInputLoading: Sendable {
    func reloadInput(
        _ input: ReadingInputSource,
        previousSnapshot: VaultSnapshot?,
        changes: VaultReloadChanges?,
        progress: (@Sendable (VaultLoadingProgress) -> Void)?
    ) throws -> VaultSnapshot
}

public struct VaultReadingInputLoader: ReadingInputLoading {
    private let vaultReader: VaultReader

    public init(vaultReader: VaultReader = VaultReader()) {
        self.vaultReader = vaultReader
    }

    public func reloadInput(
        _ input: ReadingInputSource,
        previousSnapshot: VaultSnapshot?,
        changes: VaultReloadChanges?,
        progress: (@Sendable (VaultLoadingProgress) -> Void)? = nil
    ) throws -> VaultSnapshot {
        let reader = vaultReader.with(noteFormat: VaultNoteFormat(input: input))
        switch input.kind {
        case .folder:
            return try reader.reloadVault(
                at: input.url,
                previousSnapshot: previousSnapshot,
                changes: changes,
                progress: progress
            )
        case .markdownFile:
            return try reader.reloadMarkdownFile(
                at: input.url,
                previousSnapshot: previousSnapshot,
                progress: progress
            )
        }
    }
}

public struct VaultLoadingInputLoader: ReadingInputLoading {
    private let vaultLoader: any VaultLoading

    public init(vaultLoader: any VaultLoading) {
        self.vaultLoader = vaultLoader
    }

    public func reloadInput(
        _ input: ReadingInputSource,
        previousSnapshot: VaultSnapshot?,
        changes: VaultReloadChanges?,
        progress: (@Sendable (VaultLoadingProgress) -> Void)? = nil
    ) throws -> VaultSnapshot {
        switch input.kind {
        case .folder:
            if let vaultReader = vaultLoader as? VaultReader {
                return try vaultReader.with(noteFormat: VaultNoteFormat(input: input)).reloadVault(
                    at: input.url,
                    previousSnapshot: previousSnapshot,
                    changes: changes,
                    progress: progress
                )
            }
            return try vaultLoader.reloadVault(
                at: input.url,
                previousSnapshot: previousSnapshot,
                changes: changes,
                progress: progress
            )
        case .markdownFile:
            if let vaultReader = vaultLoader as? VaultReader {
                return try vaultReader.with(noteFormat: VaultNoteFormat(input: input)).reloadMarkdownFile(
                    at: input.url,
                    previousSnapshot: previousSnapshot,
                    progress: progress
                )
            }
            return try vaultLoader.reloadVault(
                at: input.rootURL,
                previousSnapshot: previousSnapshot,
                changes: changes,
                progress: progress
            )
        }
    }
}
