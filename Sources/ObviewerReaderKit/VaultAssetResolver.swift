import Foundation
import ObviewerCore

/// Resolves reader asset requests against the open folder, read-only.
///
/// Order: the literal path relative to the folder root, then Obsidian-style
/// lookup by file name from the requesting note. Paths that escape the root
/// are rejected before touching the file system.
public struct VaultAssetResolver: VaultAssetResolving {
    public let rootURL: URL
    public let snapshot: VaultSnapshot?

    public init(rootURL: URL, snapshot: VaultSnapshot?) {
        self.rootURL = rootURL.standardizedFileURL
        self.snapshot = snapshot
    }

    public func resolveAsset(path: String, raw: String?, fromNoteID: String?) -> URL? {
        if let literal = Self.containedURL(forRelativePath: path, in: rootURL),
           FileManager.default.isReadableFile(atPath: literal.path),
           Self.isRegularFile(literal) {
            return literal
        }

        guard let snapshot else { return nil }
        let candidates = [raw, path].compactMap { $0 }.filter { $0.isEmpty == false }
        for candidate in candidates {
            let trimmed = candidate.hasPrefix("/") ? String(candidate.dropFirst()) : candidate
            if let attachment = snapshot.attachment(for: trimmed, from: fromNoteID),
               Self.isContained(attachment.url, in: rootURL) {
                return attachment.url
            }
        }
        return nil
    }

    /// Joins `relativePath` onto `root`, refusing absolute paths and `..` escapes.
    public static func containedURL(forRelativePath relativePath: String, in root: URL) -> URL? {
        var components = [String]()
        for segment in relativePath.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".":
                continue
            case "..":
                guard components.isEmpty == false else { return nil }
                components.removeLast()
            default:
                components.append(String(segment))
            }
        }
        guard components.isEmpty == false else { return nil }
        let url = components.reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL
        return isContained(url, in: root) ? url : nil
    }

    public static func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        return filePath == rootPath || filePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
