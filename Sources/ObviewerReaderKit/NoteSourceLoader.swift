import Foundation

/// Reads note files for the reader. Read-only, size-capped, and tolerant of
/// files that aren't valid UTF-8 (older Windows notes, DokuWiki exports).
public enum NoteSourceLoader {
    public static let maximumNoteBytes = 16 * 1024 * 1024

    public enum LoadError: LocalizedError {
        case tooLarge(Int)
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .tooLarge(let bytes):
                let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                return "This file is \(size), which is larger than Obviewer will render."
            case .unreadable(let path):
                return "Obviewer couldn't read \(path)."
            }
        }
    }

    public static func load(_ url: URL, maximumBytes: Int = maximumNoteBytes) throws -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > maximumBytes {
            throw LoadError.tooLarge(size)
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw LoadError.unreadable(url.lastPathComponent)
        }
        defer { try? handle.close() }
        let data = (try handle.read(upToCount: maximumBytes + 1)) ?? Data()
        if data.count > maximumBytes {
            throw LoadError.tooLarge(data.count)
        }
        return decode(data)
    }

    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return text }
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .windowsCP1252) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }
}
