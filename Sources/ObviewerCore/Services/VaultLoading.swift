import Foundation

public struct VaultLoadingProgress: Sendable, Equatable {
    public let processedFileCount: Int
    public let noteCount: Int
    public let attachmentCount: Int
    public let currentPath: String?

    public init(
        processedFileCount: Int,
        noteCount: Int,
        attachmentCount: Int,
        currentPath: String?
    ) {
        self.processedFileCount = processedFileCount
        self.noteCount = noteCount
        self.attachmentCount = attachmentCount
        self.currentPath = currentPath
    }
}

public protocol VaultLoading: Sendable {
    func loadVault(
        at url: URL,
        progress: (@Sendable (VaultLoadingProgress) -> Void)?
    ) throws -> VaultSnapshot

    func reloadVault(
        at url: URL,
        previousSnapshot: VaultSnapshot?,
        progress: (@Sendable (VaultLoadingProgress) -> Void)?
    ) throws -> VaultSnapshot
}

public extension VaultLoading {
    func loadVault(at url: URL) throws -> VaultSnapshot {
        try loadVault(at: url, progress: nil)
    }

    func reloadVault(
        at url: URL,
        previousSnapshot: VaultSnapshot?,
        progress: (@Sendable (VaultLoadingProgress) -> Void)? = nil
    ) throws -> VaultSnapshot {
        try loadVault(at: url, progress: progress)
    }
}
