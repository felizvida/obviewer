import Darwin
import Foundation

protocol VaultWatchSession: AnyObject {
    func invalidate()
}

@MainActor
protocol VaultWatching {
    func beginWatching(url: URL, onChange: @escaping @Sendable () -> Void) -> any VaultWatchSession
}

@MainActor
final class VaultWatcher: VaultWatching {
    func beginWatching(url: URL, onChange: @escaping @Sendable () -> Void) -> any VaultWatchSession {
        RecursiveVaultWatchSession(rootURL: url, onChange: onChange)
    }
}

private final class RecursiveVaultWatchSession: VaultWatchSession {
    private let rootURL: URL
    private let onChange: @Sendable () -> Void
    private let coordinationQueue = DispatchQueue(label: "com.felizvida.obviewer.vaultwatch.coordination")
    private let callbackQueue = DispatchQueue(label: "com.felizvida.obviewer.vaultwatch.callback")
    private var observers = [String: DirectoryObserver]()
    private var pendingNotification: DispatchWorkItem?
    private var isInvalidated = false

    init(rootURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.rootURL = rootURL
        self.onChange = onChange
        coordinationQueue.sync {
            refreshObservers()
        }
    }

    func invalidate() {
        coordinationQueue.sync {
            guard isInvalidated == false else {
                return
            }

            isInvalidated = true
            pendingNotification?.cancel()
            pendingNotification = nil

            let existingObservers = observers.values
            observers.removeAll()
            existingObservers.forEach { $0.invalidate() }
        }
    }

    deinit {
        invalidate()
    }

    private func handleObservedChange() {
        coordinationQueue.async {
            guard self.isInvalidated == false else {
                return
            }

            self.pendingNotification?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.coordinationQueue.sync {
                    guard self.isInvalidated == false else {
                        return
                    }
                    self.refreshObservers()
                }
                DispatchQueue.main.async(execute: self.onChange)
            }

            self.pendingNotification = workItem
            self.callbackQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        }
    }

    private func refreshObservers() {
        let directoryPaths = watchedDirectoryPaths()

        for path in observers.keys where directoryPaths.contains(path) == false {
            observers[path]?.invalidate()
            observers[path] = nil
        }

        for path in directoryPaths where observers[path] == nil {
            if let observer = DirectoryObserver(
                path: path,
                onChange: { [weak self] in
                    self?.handleObservedChange()
                }
            ) {
                observers[path] = observer
            }
        }
    }

    private func watchedDirectoryPaths() -> Set<String> {
        var paths = Set([rootURL.path])
        let keys: Set<URLResourceKey> = [.isDirectoryKey]

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return paths
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                paths.insert(url.path)
            }
        }

        return paths
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
