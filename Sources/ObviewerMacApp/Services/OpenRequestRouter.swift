import AppKit
import ObviewerCore
import SwiftUI

/// Identifies a note window. Carries a read-only security-scoped bookmark so
/// SwiftUI can restore the window after relaunch with file access intact.
public struct NoteWindowRequest: Codable, Hashable, Sendable {
    public let path: String
    public let bookmark: Data?

    public init(url: URL) {
        path = url.standardizedFileURL.path
        bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves the file, starting security-scoped access when a bookmark is available.
    public func resolveURL() -> URL {
        if let bookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        return URL(fileURLWithPath: path)
    }
}

public enum SceneID {
    public static let library = "library"
    public static let note = "note-window"
}

/// Routes files opened from Finder (double-click, "Open With", drag onto the
/// Dock icon), File › Open, Open Recent, and links between windows.
/// Note files get their own window; folders open in the library window.
@MainActor
public final class OpenRequestRouter: ObservableObject {
    public static let shared = OpenRequestRouter()

    @Published public private(set) var pendingFolders: [URL] = []
    private var pendingFiles: [URL] = []
    private var openWindow: OpenWindowAction?

    /// Called by every scene once it is on screen so the router can open windows.
    func attach(_ openWindow: OpenWindowAction) {
        self.openWindow = openWindow
        flush()
    }

    public func open(_ urls: [URL]) {
        for url in urls {
            let standardized = url.standardizedFileURL
            let isDirectory = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                pendingFolders.append(standardized)
            } else if NoteFileTypes.isNoteFile(standardized) {
                pendingFiles.append(standardized)
            }
        }
        flush()
    }

    /// Shows the file picker and routes the choice.
    public func chooseAndOpen() {
        guard let url = VaultPicker().chooseVault() else { return }
        open([url])
    }

    public func showLibrary() {
        openWindow?(id: SceneID.library)
    }

    func takePendingFolder() -> URL? {
        guard pendingFolders.isEmpty == false else { return nil }
        return pendingFolders.removeFirst()
    }

    private func flush() {
        guard let openWindow else { return }
        if pendingFolders.isEmpty == false {
            // Brings the library window forward (or reopens it); it consumes pendingFolders.
            openWindow(id: SceneID.library)
        }
        while pendingFiles.isEmpty == false {
            let url = pendingFiles.removeFirst()
            openWindow(id: SceneID.note, value: NoteWindowRequest(url: url))
        }
    }
}

/// App delegate that receives Finder open events.
public final class ObviewerAppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: ReaderKeyMonitor?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let monitor = ReaderKeyMonitor()
            monitor.start()
            keyMonitor = monitor
        }
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            OpenRequestRouter.shared.open(urls)
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
