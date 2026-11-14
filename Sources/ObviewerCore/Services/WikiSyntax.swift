import Foundation

/// Kinds of things an `![[embed]]` can point at, judged by file extension.
public enum WikiEmbedKind: String, Sendable {
    case note
    case image
    case pdf
    case audio
    case video
    case file
}

/// A parsed `[[target#anchor|alias]]`.
public struct WikiTarget: Equatable, Sendable {
    /// Everything before the alias, trimmed (`Note#Heading`). Used as the embed key.
    public let raw: String
    /// The note or file part (`Note`), empty for same-note anchors.
    public let note: String
    /// The last `#anchor` segment, if any (`Heading` or `^block-id`).
    public let anchor: String?
    public let alias: String?
}

/// Small, dependency-free scanners for wiki-style syntax. These mirror
/// `Renderer/src/core/util.js` so the indexer and the renderer agree on
/// what counts as a link (see `Fixtures/notes/expectations.json`).
public enum WikiSyntax {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp", "avif", "tif", "tiff"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "ogg", "flac", "aac"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "webm", "m4v"]
    public static let noteExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    public static func parseTarget(_ inner: String) -> WikiTarget {
        let text = inner.replacingOccurrences(of: "\\|", with: "|")
        let targetPart: Substring
        let alias: String?
        if let pipe = text.firstIndex(of: "|") {
            targetPart = text[..<pipe]
            alias = text[text.index(after: pipe)...].trimmingCharacters(in: .whitespaces)
        } else {
            targetPart = Substring(text)
            alias = nil
        }
        let raw = targetPart.trimmingCharacters(in: .whitespaces)
        let segments = raw.components(separatedBy: "#")
        let note = segments[0].trimmingCharacters(in: .whitespaces)
        let anchors = segments.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
        return WikiTarget(raw: raw, note: note, anchor: anchors.last, alias: alias)
    }

    public static func embedKind(forPath path: String) -> WikiEmbedKind {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext.isEmpty || noteExtensions.contains(ext) || ext == "txt" { return .note }
        if imageExtensions.contains(ext) { return .image }
        if audioExtensions.contains(ext) { return .audio }
        if videoExtensions.contains(ext) { return .video }
        if ext == "pdf" { return .pdf }
        return .file
    }

    /// Inner text of every `![[...]]` outside code.
    public static func embedContents(in source: String) -> [String] {
        matches(in: stripCode(source), embedsOnly: true)
    }

    /// Inner text of every `[[...]]` and `![[...]]` outside code.
    public static func wikiLinkContents(in source: String) -> [String] {
        matches(in: stripCode(source), embedsOnly: false)
    }

    private static func matches(in text: String, embedsOnly: Bool) -> [String] {
        var results = [String]()
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index + 1 < scalars.count {
            guard scalars[index] == "[", scalars[index + 1] == "[" else {
                index += 1
                continue
            }
            let isEscaped = index > 0 && scalars[index - 1] == "\\"
            // "\![[x]]" is an escaped "!" followed by a plain link, as in the renderer.
            let isEmbed = index > 0 && scalars[index - 1] == "!" && (index < 2 || scalars[index - 2] != "\\")
            var end = index + 2
            var found = false
            while end + 1 < scalars.count {
                if scalars[end] == "\n" { break }
                if scalars[end] == "]" && scalars[end + 1] == "]" {
                    found = true
                    break
                }
                end += 1
            }
            guard found else {
                index += 2
                continue
            }
            var inner = String.UnicodeScalarView()
            inner.append(contentsOf: scalars[(index + 2)..<end])
            let content = String(inner)
            if isEscaped == false,
               content.trimmingCharacters(in: .whitespaces).isEmpty == false,
               content.contains("[[") == false,
               embedsOnly == false || isEmbed {
                results.append(content)
            }
            index = end + 2
        }
        return results
    }

    /// Removes fenced code blocks and inline code spans so links inside code are ignored.
    public static func stripCode(_ source: String) -> String {
        var output = [String]()
        var fence: (character: Character, length: Int)?
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.drop(while: { $0 == " " })
            let leadingSpaces = line.count - trimmed.count
            if let current = fence {
                let run = trimmed.prefix(while: { $0 == current.character })
                if leadingSpaces <= 3, run.count >= current.length,
                   trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                output.append("")
                continue
            }
            if leadingSpaces <= 3, let first = trimmed.first, first == "`" || first == "~" {
                let run = trimmed.prefix(while: { $0 == first })
                if run.count >= 3 {
                    fence = (first, run.count)
                    output.append("")
                    continue
                }
            }
            output.append(stripInlineCode(line))
        }
        return output.joined(separator: "\n")
    }

    private static func stripInlineCode(_ line: String) -> String {
        guard line.contains("`") else { return line }
        var result = ""
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "`" {
                let runEnd = line[index...].firstIndex(where: { $0 != "`" }) ?? line.endIndex
                let delimiter = String(line[index..<runEnd])
                if let close = line.range(of: delimiter, range: runEnd..<line.endIndex) {
                    index = close.upperBound
                    continue
                }
                result += delimiter
                index = runEnd
                continue
            }
            result.append(line[index])
            index = line.index(after: index)
        }
        return result
    }
}
