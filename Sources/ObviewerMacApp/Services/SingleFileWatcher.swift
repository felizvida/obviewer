import Darwin
import Foundation

@MainActor
protocol SingleFileWatching {
    func beginWatching(fileURL: URL, onChange: @escaping @Sendable () -> Void) -> any VaultWatchSession
}

/// Watches one file for changes, including the atomic "write temp file, then
/// rename over the original" saves most editors use. Opens the file with
/// O_EVTONLY, which reads nothing and never writes.
@MainActor
final class SingleFileWatcher: SingleFileWatching {
    func beginWatching(fileURL: URL, onChange: @escaping @Sendable () -> Void) -> any VaultWatchSession {
        SingleFileWatchSession(fileURL: fileURL, onChange: onChange)
    }
}

private final class SingleFileWatchSession: VaultWatchSession, @unchecked Sendable {
    private let fileURL: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.felizvida.obviewer.filewatch")
    private var source: DispatchSourceFileSystemObject?
    private var pendingNotify: DispatchWorkItem?
    private var lastModified: Date?
    private var isInvalidated = false

    init(fileURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        queue.async { [weak self] in
            guard let self else { return }
            self.lastModified = self.modificationDate()
            self.arm(retries: 0)
        }
    }

    deinit {
        pendingNotify?.cancel()
        source?.cancel()
    }

    func invalidate() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isInvalidated = true
            self.pendingNotify?.cancel()
            self.source?.cancel()
            self.source = nil
        }
    }

    private func arm(retries: Int) {
        guard isInvalidated == false else { return }
        let descriptor = open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // The file may be mid-replacement; try again shortly.
            if retries < 20 {
                queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.arm(retries: retries + 1) }
            }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .attrib, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
                source.cancel()
                self.source = nil
                self.queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.arm(retries: 0) }
            }
            self.scheduleNotify()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    private func scheduleNotify() {
        pendingNotify?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isInvalidated == false else { return }
            let modified = self.modificationDate()
            guard modified != self.lastModified else { return }
            self.lastModified = modified
            self.onChange()
        }
        pendingNotify = work
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func modificationDate() -> Date? {
        // FileManager instead of URL.resourceValues: URL caches resource values per instance.
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }
}
