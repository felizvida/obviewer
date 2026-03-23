import Darwin
import Foundation
import ObviewerCore

protocol VaultWatchSession: AnyObject {
    func invalidate()
}

@MainActor
protocol VaultWatching {
    func beginWatching(
        url: URL,
        onChange: @escaping @Sendable (VaultReloadChanges) -> Void
    ) -> any VaultWatchSession
}

@MainActor
final class VaultWatcher: VaultWatching {
    func beginWatching(
        url: URL,
        onChange: @escaping @Sendable (VaultReloadChanges) -> Void
    ) -> any VaultWatchSession {
        RecursiveVaultWatchSession(rootURL: url, onChange: onChange)
    }
}

private final class RecursiveVaultWatchSession: VaultWatchSession {
    private let normalizedRootURL: URL
    private let onChange: @Sendable (VaultReloadChanges) -> Void
    private let coordinationQueue = DispatchQueue(label: "com.felizvida.obviewer.vaultwatch.coordination")
    private let callbackQueue = DispatchQueue(label: "com.felizvida.obviewer.vaultwatch.callback")
    private var observers = [String: DirectoryObserver]()
    private var directorySnapshots = [String: DirectoryContentsSnapshot]()
    private var fileInventory = [String: WatchedFileSnapshot]()
    private var pendingDirectoryPaths = Set<String>()
    private var pendingDispatchWorkItem: DispatchWorkItem?
    private var isInvalidated = false

    init(rootURL: URL, onChange: @escaping @Sendable (VaultReloadChanges) -> Void) {
        normalizedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.onChange = onChange
        coordinationQueue.sync {
            installTree(at: normalizedRootURL)
        }
    }

    func invalidate() {
        coordinationQueue.sync {
            guard isInvalidated == false else {
                return
            }

            isInvalidated = true
            pendingDispatchWorkItem?.cancel()
            pendingDispatchWorkItem = nil
            pendingDirectoryPaths.removeAll()
            directorySnapshots.removeAll()
            fileInventory.removeAll()

            let existingObservers = observers.values
            observers.removeAll()
            existingObservers.forEach { $0.invalidate() }
        }
    }

    deinit {
        invalidate()
    }

    private func handleObservedChange(at absoluteDirectoryPath: String) {
        coordinationQueue.async {
            guard self.isInvalidated == false else {
                return
            }

            self.pendingDirectoryPaths.insert(absoluteDirectoryPath)
            self.pendingDispatchWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let changes = self.coordinationQueue.sync { () -> VaultReloadChanges in
                    guard self.isInvalidated == false else {
                        return .none
                    }

                    return self.flushPendingChanges()
                }

                guard changes.isEmpty == false else {
                    return
                }

                DispatchQueue.main.async {
                    self.onChange(changes)
                }
            }

            self.pendingDispatchWorkItem = workItem
            self.callbackQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        }
    }

    private func flushPendingChanges() -> VaultReloadChanges {
        let directoryPaths = pendingDirectoryPaths.sorted { lhs, rhs in
            let lhsDepth = lhs.split(separator: "/").count
            let rhsDepth = rhs.split(separator: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        pendingDirectoryPaths.removeAll()

        var changes = VaultReloadChanges.none
        for path in directoryPaths {
            changes = changes.merged(with: rescanDirectory(at: path))
        }

        return changes
    }

    private func rescanDirectory(at absolutePath: String) -> VaultReloadChanges {
        let directoryURL = URL(fileURLWithPath: absolutePath, isDirectory: true)

        guard let currentSnapshot = scanImmediateDirectory(at: directoryURL) else {
            if absolutePath == normalizedRootURL.path {
                return VaultReloadChanges(requiresFullReload: true)
            }

            var removedPaths = Set<String>()
            removeTree(at: absolutePath, removedPaths: &removedPaths)
            return VaultReloadChanges(removedPaths: removedPaths)
        }

        let previousSnapshot = directorySnapshots[absolutePath]
        directorySnapshots[absolutePath] = currentSnapshot
        ensureObserver(for: absolutePath)

        guard let previousSnapshot else {
            var createdPaths = Set<String>()
            installTree(at: directoryURL, createdPaths: &createdPaths)
            return VaultReloadChanges(createdPaths: createdPaths)
        }

        var modifiedPaths = Set<String>()
        var createdPaths = Set<String>()
        var removedPaths = Set<String>()
        let entryNames = Set(previousSnapshot.entries.keys).union(currentSnapshot.entries.keys)

        for entryName in entryNames.sorted(by: { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }) {
            let oldEntry = previousSnapshot.entries[entryName]
            let newEntry = currentSnapshot.entries[entryName]
            let childURL = directoryURL.appendingPathComponent(entryName, isDirectory: newEntry?.kind == .directory)
            let childPath = childURL.path

            switch (oldEntry, newEntry) {
            case (nil, .some(let entry)):
                handleCreatedEntry(entry, at: childURL, createdPaths: &createdPaths)

            case (.some(let entry), nil):
                handleRemovedEntry(entry, at: childPath, removedPaths: &removedPaths)

            case (.some(let oldEntry), .some(let newEntry)):
                if oldEntry.kind != newEntry.kind {
                    handleRemovedEntry(oldEntry, at: childPath, removedPaths: &removedPaths)
                    handleCreatedEntry(newEntry, at: childURL, createdPaths: &createdPaths)
                    continue
                }

                guard oldEntry.kind == .file else {
                    continue
                }

                if oldEntry.modifiedAt != newEntry.modifiedAt,
                   let relativePath = relativePath(for: childURL) {
                    fileInventory[relativePath] = WatchedFileSnapshot(
                        relativePath: relativePath,
                        modifiedAt: newEntry.modifiedAt ?? .distantPast
                    )
                    modifiedPaths.insert(relativePath)
                }

            case (nil, nil):
                continue
            }
        }

        return VaultReloadChanges(
            modifiedPaths: modifiedPaths,
            createdPaths: createdPaths,
            removedPaths: removedPaths
        )
    }

    private func handleCreatedEntry(
        _ entry: DirectoryEntrySnapshot,
        at url: URL,
        createdPaths: inout Set<String>
    ) {
        switch entry.kind {
        case .directory:
            installTree(at: url, createdPaths: &createdPaths)
        case .file:
            guard let relativePath = relativePath(for: url) else {
                return
            }

            fileInventory[relativePath] = WatchedFileSnapshot(
                relativePath: relativePath,
                modifiedAt: entry.modifiedAt ?? .distantPast
            )
            createdPaths.insert(relativePath)
        }
    }

    private func installTree(at directoryURL: URL) {
        var ignoredCreatedPaths = Set<String>()
        installTree(at: directoryURL, createdPaths: &ignoredCreatedPaths)
    }

    private func handleRemovedEntry(
        _ entry: DirectoryEntrySnapshot,
        at absolutePath: String,
        removedPaths: inout Set<String>
    ) {
        switch entry.kind {
        case .directory:
            removeTree(at: absolutePath, removedPaths: &removedPaths)
        case .file:
            guard let relativePath = relativePath(forAbsolutePath: absolutePath) else {
                return
            }

            fileInventory.removeValue(forKey: relativePath)
            removedPaths.insert(relativePath)
        }
    }

    private func installTree(at directoryURL: URL, createdPaths: inout Set<String>) {
        let absolutePath = directoryURL.path
        guard let snapshot = scanImmediateDirectory(at: directoryURL) else {
            return
        }

        directorySnapshots[absolutePath] = snapshot
        ensureObserver(for: absolutePath)

        for (entryName, entry) in snapshot.entries {
            let childURL = directoryURL.appendingPathComponent(entryName, isDirectory: entry.kind == .directory)
            switch entry.kind {
            case .directory:
                installTree(at: childURL, createdPaths: &createdPaths)
            case .file:
                guard let relativePath = relativePath(for: childURL) else {
                    continue
                }

                fileInventory[relativePath] = WatchedFileSnapshot(
                    relativePath: relativePath,
                    modifiedAt: entry.modifiedAt ?? .distantPast
                )
                createdPaths.insert(relativePath)
            }
        }
    }

    private func removeTree(at absolutePath: String, removedPaths: inout Set<String>) {
        let normalizedPath = absolutePath.hasSuffix("/") ? String(absolutePath.dropLast()) : absolutePath
        let pathPrefix = normalizedPath + "/"

        let removedFiles = fileInventory.keys.filter { relativePath in
            guard let absoluteURL = absoluteURL(forRelativePath: relativePath) else {
                return false
            }

            return absoluteURL.path == normalizedPath || absoluteURL.path.hasPrefix(pathPrefix)
        }

        for relativePath in removedFiles {
            fileInventory.removeValue(forKey: relativePath)
            removedPaths.insert(relativePath)
        }

        let removedDirectories = directorySnapshots.keys.filter { candidatePath in
            candidatePath == normalizedPath || candidatePath.hasPrefix(pathPrefix)
        }

        for directoryPath in removedDirectories {
            directorySnapshots.removeValue(forKey: directoryPath)
            observers[directoryPath]?.invalidate()
            observers[directoryPath] = nil
        }
    }

    private func ensureObserver(for absolutePath: String) {
        guard observers[absolutePath] == nil else {
            return
        }

        observers[absolutePath] = DirectoryObserver(
            path: absolutePath,
            onChange: { [weak self] in
                self?.handleObservedChange(at: absolutePath)
            }
        )
    }

    private func scanImmediateDirectory(at directoryURL: URL) -> DirectoryContentsSnapshot? {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .nameKey,
        ]

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var entries = [String: DirectoryEntrySnapshot]()
        for url in contents {
            let values = try? url.resourceValues(forKeys: keys)
            let entryName = values?.name ?? url.lastPathComponent

            if values?.isDirectory == true {
                entries[entryName] = DirectoryEntrySnapshot(kind: .directory)
            } else if values?.isRegularFile == true {
                entries[entryName] = DirectoryEntrySnapshot(
                    kind: .file,
                    modifiedAt: values?.contentModificationDate ?? .distantPast
                )
            }
        }

        return DirectoryContentsSnapshot(entries: entries)
    }

    private func relativePath(for url: URL) -> String? {
        let normalizedFileURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = normalizedRootURL.pathComponents
        let fileComponents = normalizedFileURL.pathComponents

        guard fileComponents.starts(with: rootComponents) else {
            return nil
        }

        let relativeComponents = fileComponents.dropFirst(rootComponents.count)
        let relativePath = relativeComponents.joined(separator: "/")
        return relativePath.isEmpty ? nil : relativePath
    }

    private func relativePath(forAbsolutePath absolutePath: String) -> String? {
        relativePath(for: URL(fileURLWithPath: absolutePath))
    }

    private func absoluteURL(forRelativePath relativePath: String) -> URL? {
        guard relativePath.isEmpty == false else {
            return nil
        }

        return normalizedRootURL.appending(path: relativePath)
    }
}

private final class DirectoryObserver {
    private let fileDescriptor: Int32
    private let source: DispatchSourceFileSystemObject
    private var isInvalidated = false

    init?(path: String, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        fileDescriptor = descriptor
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    func invalidate() {
        guard isInvalidated == false else {
            return
        }

        isInvalidated = true
        source.cancel()
    }
}

private struct DirectoryContentsSnapshot {
    let entries: [String: DirectoryEntrySnapshot]
}

private struct DirectoryEntrySnapshot: Equatable {
    enum Kind: Equatable {
        case directory
        case file
    }

    let kind: Kind
    let modifiedAt: Date?

    init(kind: Kind, modifiedAt: Date? = nil) {
        self.kind = kind
        self.modifiedAt = modifiedAt
    }
}

private struct WatchedFileSnapshot {
    let relativePath: String
    let modifiedAt: Date
}
