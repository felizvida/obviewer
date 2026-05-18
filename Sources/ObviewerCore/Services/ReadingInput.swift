import Foundation

public enum ReadingProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case markdown
    case obsidian

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .obsidian:
            return "Obsidian"
        }
    }
}

public enum ReadingInputKind: String, Codable, Sendable {
    case folder
    case markdownFile
}

public struct ReadingInputSource: Equatable, Sendable {
    public let url: URL
    public let kind: ReadingInputKind
    public let profile: ReadingProfile

    public init(url: URL, kind: ReadingInputKind, profile: ReadingProfile) {
        self.url = url.standardizedFileURL
        self.kind = kind
        self.profile = profile
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

    public var focusRelativePath: String? {
        switch kind {
        case .folder:
            return nil
        case .markdownFile:
            return url.lastPathComponent
        }
    }
}

public protocol ReadingInputAdapting: Sendable {
    func makeInputSource(for url: URL, preferredProfile: ReadingProfile?) -> ReadingInputSource
}

public struct DefaultReadingInputAdapter: ReadingInputAdapting {
    public init() {}

    public func makeInputSource(for url: URL, preferredProfile: ReadingProfile? = nil) -> ReadingInputSource {
        let standardizedURL = url.standardizedFileURL
        if standardizedURL.pathExtension.lowercased() == "md", isDirectory(standardizedURL) == false {
            return ReadingInputSource(
                url: standardizedURL,
                kind: .markdownFile,
                profile: preferredProfile ?? .markdown
            )
        }

        return ReadingInputSource(
            url: standardizedURL,
            kind: .folder,
            profile: preferredProfile ?? detectedFolderProfile(for: standardizedURL)
        )
    }

    private func detectedFolderProfile(for url: URL) -> ReadingProfile {
        let obsidianDirectory = url.appending(path: ".obsidian", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: obsidianDirectory.path) {
            return .obsidian
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

public extension ReadingInputLoading {
    func loadInput(
        _ input: ReadingInputSource,
        progress: (@Sendable (VaultLoadingProgress) -> Void)? = nil
    ) throws -> VaultSnapshot {
        try reloadInput(input, previousSnapshot: nil, changes: nil, progress: progress)
    }
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
        switch input.kind {
        case .folder:
            return try vaultReader.reloadVault(
                at: input.url,
                previousSnapshot: previousSnapshot,
                changes: changes,
                progress: progress
            )
        case .markdownFile:
            return try vaultReader.reloadMarkdownFile(
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
            return try vaultLoader.reloadVault(
                at: input.url,
                previousSnapshot: previousSnapshot,
                changes: changes,
                progress: progress
            )
        case .markdownFile:
            if let vaultReader = vaultLoader as? VaultReader {
                return try vaultReader.reloadMarkdownFile(
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
