import Foundation
import UniformTypeIdentifiers

/// Locates the offline reader bundle (HTML, JS, CSS, Mermaid, KaTeX) that
/// `Renderer/build.mjs` writes into `Resources/Reader`.
public enum ReaderAssets {
    /// Folder that contains `reader.html`.
    public static var directoryURL: URL? {
        resourceBundle.url(forResource: "Reader", withExtension: nil)
            ?? resourceBundle.resourceURL?.appendingPathComponent("Reader", isDirectory: true)
    }

    public static let isAvailable: Bool = {
        guard let directoryURL else { return false }
        return FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("reader.html").path)
    }()

    /// Reads a bundled file by its path relative to the Reader folder.
    /// Returns nil for anything outside the folder.
    public static func data(forRelativePath relativePath: String) -> Data? {
        guard let directoryURL else { return nil }
        let cleaned = relativePath.split(separator: "/").filter { $0 != "." && $0.isEmpty == false }
        guard cleaned.contains("..") == false, cleaned.isEmpty == false else { return nil }
        let fileURL = cleaned.reduce(directoryURL) { $0.appendingPathComponent(String($1)) }
        let root = directoryURL.standardizedFileURL.path
        guard fileURL.standardizedFileURL.path.hasPrefix(root + "/") else { return nil }
        return try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
    }

    public static func mimeType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "txt", "md", "markdown": return "text/plain"
        default:
            return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: ReaderAssetsBundleToken.self)
        #endif
    }
}

private final class ReaderAssetsBundleToken {}
