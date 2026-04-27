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

public struct VaultReloadChanges: Sendable, Equatable {
    public let modifiedPaths: Set<String>
    public let createdPaths: Set<String>
    public let removedPaths: Set<String>
    public let requiresFullReload: Bool

    public init(
        modifiedPaths: Set<String> = [],
        createdPaths: Set<String> = [],
        removedPaths: Set<String> = [],
        requiresFullReload: Bool = false
    ) {
        self.modifiedPaths = modifiedPaths
        self.createdPaths = createdPaths
        self.removedPaths = removedPaths
        self.requiresFullReload = requiresFullReload
    }

    public static let none = VaultReloadChanges()

    public var isEmpty: Bool {
        modifiedPaths.isEmpty
            && createdPaths.isEmpty
            && removedPaths.isEmpty
            && requiresFullReload == false
    }

    public var affectedPaths: [String] {
        Array(modifiedPaths.union(createdPaths).union(removedPaths)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public func merged(with other: VaultReloadChanges) -> VaultReloadChanges {
        let combinedCreatedPaths = createdPaths.union(other.createdPaths)
        let combinedRemovedPaths = removedPaths.union(other.removedPaths)
        // If a path is both removed and created while we are coalescing async filesystem
        // events, we can no longer safely infer its original existence. Treat it as a
        // modified path so the next reload revalidates the current on-disk state.
        let conflictedPaths = combinedCreatedPaths.intersection(combinedRemovedPaths)
        let survivingCreatedPaths = combinedCreatedPaths.subtracting(conflictedPaths)
        let survivingRemovedPaths = combinedRemovedPaths.subtracting(conflictedPaths)
        let survivingModifiedPaths = modifiedPaths
            .union(other.modifiedPaths)
            .union(conflictedPaths)
            .subtracting(survivingCreatedPaths)
            .subtracting(survivingRemovedPaths)

        return VaultReloadChanges(
            modifiedPaths: survivingModifiedPaths,
            createdPaths: survivingCreatedPaths,
            removedPaths: survivingRemovedPaths,
            requiresFullReload: requiresFullReload || other.requiresFullReload
        )
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
        changes: VaultReloadChanges?,
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
        try reloadVault(
            at: url,
            previousSnapshot: previousSnapshot,
            changes: nil,
            progress: progress
        )
    }

    func reloadVault(
        at url: URL,
        previousSnapshot: VaultSnapshot?,
        changes: VaultReloadChanges?,
        progress: (@Sendable (VaultLoadingProgress) -> Void)? = nil
    ) throws -> VaultSnapshot {
        try loadVault(at: url, progress: progress)
    }
}
