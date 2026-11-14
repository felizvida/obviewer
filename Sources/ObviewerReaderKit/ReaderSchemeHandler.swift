import Foundation
import WebKit

/// Serves `obviewer-asset://` requests:
///   obviewer-asset://app/<path>    files from the bundled Reader folder
///   obviewer-asset://vault/<path>  files from the open folder, via `VaultAssetResolving`
///
/// It only ever reads. Requests for anything outside the bundle or the open
/// folder fail with 404.
public final class ReaderSchemeHandler: NSObject, WKURLSchemeHandler {
    public nonisolated static let scheme = "obviewer-asset"
    public nonisolated static let readerPageURL = URL(string: "obviewer-asset://app/reader.html")!

    /// Upper bound for a single vault file served to the page.
    public nonisolated static let maximumAssetBytes = 64 * 1024 * 1024

    /// Receives one line per request ("GET obviewer-asset://app/reader.js -> 200") for diagnostics.
    public var onLog: (@Sendable (String) -> Void)?

    private let lock = NSLock()
    private var activeTasks = Set<ObjectIdentifier>()
    private var resolver: (any VaultAssetResolving)?
    private let queue = DispatchQueue(label: "obviewer.reader.assets", qos: .userInitiated, attributes: .concurrent)

    public override init() {
        super.init()
    }

    public func setResolver(_ resolver: (any VaultAssetResolving)?) {
        lock.lock()
        self.resolver = resolver
        lock.unlock()
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        lock.lock()
        activeTasks.insert(taskID)
        let resolver = self.resolver
        lock.unlock()

        guard let url = urlSchemeTask.request.url else {
            finish(urlSchemeTask, taskID: taskID, result: .failure(404))
            return
        }

        let rangeHeader = urlSchemeTask.request.value(forHTTPHeaderField: "Range")
        queue.async { [weak self] in
            let result = Self.load(url: url, range: rangeHeader, resolver: resolver)
            Task { @MainActor [weak self] in
                self?.finish(urlSchemeTask, taskID: taskID, result: result)
            }
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        lock.lock()
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }

    private enum LoadResult: Sendable {
        case success(Data, mimeType: String)
        /// A byte range of a larger file (audio/video seeking).
        case partial(Data, mimeType: String, start: Int, end: Int, total: Int)
        case failure(Int)
    }

    /// Largest chunk returned for an open-ended range request.
    nonisolated static let maximumRangeChunk = 8 * 1024 * 1024

    private nonisolated static func load(url: URL, range: String?, resolver: (any VaultAssetResolving)?) -> LoadResult {
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        switch url.host {
        case "app":
            guard let data = ReaderAssets.data(forRelativePath: path) else { return .failure(404) }
            return .success(data, mimeType: ReaderAssets.mimeType(forPath: path))

        case "vault":
            guard let resolver else { return .failure(404) }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query = components?.queryItems ?? []
            let raw = query.first(where: { $0.name == "raw" })?.value
            let from = query.first(where: { $0.name == "from" })?.value
            guard let fileURL = resolver.resolveAsset(path: path, raw: raw, fromNoteID: from) else {
                return .failure(404)
            }
            let mimeType = ReaderAssets.mimeType(forPath: fileURL.path)
            if let range, let requested = parseRange(range) {
                return readRange(of: fileURL, start: requested.start, end: requested.end, mimeType: mimeType)
            }
            guard let data = readFile(at: fileURL) else { return .failure(403) }
            return .success(data, mimeType: mimeType)

        default:
            return .failure(404)
        }
    }

    /// Parses "bytes=start-end" or "bytes=start-" (single range only).
    nonisolated static func parseRange(_ header: String) -> (start: Int, end: Int?)? {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("bytes="), trimmed.contains(",") == false else { return nil }
        let parts = trimmed.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Int(parts[0]), start >= 0 else { return nil }
        if parts[1].isEmpty { return (start, nil) }
        guard let end = Int(parts[1]), end >= start else { return nil }
        return (start, end)
    }

    private nonisolated static func readRange(of url: URL, start: Int, end: Int?, mimeType: String) -> LoadResult {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let total = values.fileSize else {
            return .failure(403)
        }
        guard start < total else { return .failure(416) }
        let last = min(end ?? (start + maximumRangeChunk - 1), total - 1, start + maximumRangeChunk - 1)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .failure(403) }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(start))
            let data = try handle.read(upToCount: last - start + 1) ?? Data()
            return .partial(data, mimeType: mimeType, start: start, end: start + data.count - 1, total: total)
        } catch {
            return .failure(403)
        }
    }

    private nonisolated static func readFile(at url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) <= maximumAssetBytes else {
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.readToEnd()
    }

    private func finish(_ task: any WKURLSchemeTask, taskID: ObjectIdentifier, result: LoadResult) {
        lock.lock()
        let isActive = activeTasks.remove(taskID) != nil
        lock.unlock()
        guard isActive, let url = task.request.url else { return }
        let status: Int
        switch result {
        case .success: status = 200
        case .partial: status = 206
        case .failure(let code): status = code
        }
        // Vault paths can be private; log only the bundle files in full.
        let shown = url.host == "app" ? url.absoluteString : "obviewer-asset://vault/… (\(url.pathExtension))"
        onLog?("GET \(shown) -> \(status)")

        switch result {
        case .success(let data, let mimeType):
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mimeType,
                    "Content-Length": String(data.count),
                    "Cache-Control": "no-store",
                    "Accept-Ranges": "bytes",
                    "X-Content-Type-Options": "nosniff",
                ]
            )!
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        case .partial(let data, let mimeType, let start, let end, let total):
            let response = HTTPURLResponse(
                url: url,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mimeType,
                    "Content-Length": String(data.count),
                    "Content-Range": "bytes \(start)-\(end)/\(total)",
                    "Accept-Ranges": "bytes",
                    "Cache-Control": "no-store",
                ]
            )!
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        case .failure(let status):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(response)
            task.didFinish()
        }
    }
}

/// Maps a vault asset request to a file URL the app may read.
public protocol VaultAssetResolving: Sendable {
    func resolveAsset(path: String, raw: String?, fromNoteID: String?) -> URL?
}
