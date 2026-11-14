import Foundation

/// DokuWiki page IDs, link extraction and a lightweight indexer.
/// Mirrors `Renderer/src/core/dokuwiki.js`.
public enum DokuWikiSyntax {
    // MARK: - IDs

    public static func cleanID(_ id: String) -> String {
        var value = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        value = value.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
        value = value.replacingOccurrences(of: "[/;]", with: ":", options: .regularExpression)
        value = value.replacingOccurrences(of: ":{2,}", with: ":", options: .regularExpression)
        while value.hasPrefix(":") { value.removeFirst() }
        while value.hasSuffix(":") { value.removeLast() }
        return value
    }

    /// Namespace components of the page stored at `noteID` (vault-relative path).
    public static func namespace(ofNoteID noteID: String, pagesBase: String) -> [String] {
        var path = noteID
        if pagesBase.isEmpty == false, path.hasPrefix(pagesBase + "/") {
            path = String(path.dropFirst(pagesBase.count + 1))
        }
        if path.lowercased().hasSuffix(".txt") { path = String(path.dropLast(4)) }
        var parts = path.split(separator: "/").map(String.init)
        if parts.isEmpty == false { parts.removeLast() }
        return parts
    }

    public static func resolveID(_ target: String, namespace: [String]) -> String {
        let raw = target.trimmingCharacters(in: .whitespaces)
        guard raw.isEmpty == false else { return "" }
        var parts: [String]
        if raw.hasPrefix(":") {
            parts = raw.dropFirst().components(separatedBy: ":")
        } else if raw.hasPrefix("..:") || raw.hasPrefix(".:") || raw == "." || raw == ".." {
            parts = namespace
            for segment in raw.components(separatedBy: ":") {
                if segment == ".." {
                    if parts.isEmpty == false { parts.removeLast() }
                } else if segment != "." {
                    parts.append(segment)
                }
            }
        } else if raw.contains(":") {
            parts = raw.components(separatedBy: ":")
        } else {
            parts = namespace + [raw]
        }
        if raw.hasSuffix(":") { parts.append("start") }
        return cleanID(parts.filter { $0.isEmpty == false }.joined(separator: ":"))
    }

    /// Vault-relative path (without extension) for a page ID.
    public static func pathWithoutExtension(forPageID id: String, pagesBase: String) -> String {
        let path = id.split(separator: ":").joined(separator: "/")
        return pagesBase.isEmpty ? path : "\(pagesBase)/\(path)"
    }

    public static func noteID(forPageID id: String, in snapshot: VaultSnapshot, pagesBase: String) -> String? {
        guard id.isEmpty == false else { return nil }
        let base = pathWithoutExtension(forPageID: id, pagesBase: pagesBase)
        if let note = snapshot.note(withID: base + ".txt") { return note.id }
        // Namespace start pages: "ns" may mean "ns/start.txt" or "ns/ns.txt".
        let last = id.split(separator: ":").last.map(String.init) ?? id
        for candidate in ["\(base)/start.txt", "\(base)/\(last).txt"] {
            if let note = snapshot.note(withID: candidate) { return note.id }
        }
        return snapshot.resolveNoteID(for: base)
    }

    // MARK: - Links

    private static let linkPattern = try! NSRegularExpression(pattern: #"\[\[([^\]|#]*)(?:#[^\]|]*)?(?:\|[\s\S]*?)?\]\]"#)

    public static func stripLiteralBlocks(_ source: String) -> String {
        var text = source
        for pattern in [#"<(code|file)[^>]*>[\s\S]*?</\1>"#, #"<nowiki>[\s\S]*?</nowiki>"#, #"%%[\s\S]*?%%"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return text
    }

    public static func isExternal(_ target: String) -> Bool {
        let lowered = target.lowercased()
        return lowered.contains("://") || lowered.hasPrefix("mailto:")
            || target.range(of: #"^[a-zA-Z0-9._-]+>"#, options: .regularExpression) != nil
            || target.hasPrefix("\\\\")
    }

    /// Absolute page IDs linked from `source`.
    public static func linkIDs(in source: String, fromNoteID noteID: String, pagesBase: String) -> [String] {
        let currentNamespace = namespace(ofNoteID: noteID, pagesBase: pagesBase)
        let text = stripLiteralBlocks(source)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var ids = [String]()
        for match in linkPattern.matches(in: text, range: range) {
            guard let targetRange = Range(match.range(at: 1), in: text) else { continue }
            let target = String(text[targetRange]).trimmingCharacters(in: .whitespaces)
            guard target.isEmpty == false, isExternal(target) == false else { continue }
            let id = resolveID(target, namespace: currentNamespace)
            if id.isEmpty == false, seen.insert(id).inserted { ids.append(id) }
        }
        return ids
    }

    // MARK: - Indexing

    /// Builds the index entry for a DokuWiki page. Rendering happens in the
    /// web renderer; `blocks` is only a plain-text fallback for the classic view.
    public static func parse(text: String, noteID: String, pagesBase: String, fallbackTitle: String) -> ObsidianParseResult {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var title: String?
        var toc = [TableOfContentsItem]()
        var tags = [String]()
        var anchorCounts = [String: Int]()

        for line in lines {
            if let heading = heading(in: line) {
                if title == nil, heading.level == 1 { title = heading.text }
                let slug = heading.text.lowercased()
                    .replacingOccurrences(of: #"[^\p{L}\p{N}\s_-]"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s"#, with: "-", options: .regularExpression)
                let count = anchorCounts[slug, default: 0]
                anchorCounts[slug] = count + 1
                toc.append(TableOfContentsItem(id: count == 0 ? slug : "\(slug)-\(count)", level: heading.level, title: heading.text))
            }
            if let range = line.range(of: #"\{\{tag>([^}]*)\}\}"#, options: .regularExpression) {
                let inner = line[range].dropFirst(6).dropLast(2)
                tags.append(contentsOf: inner.split(whereSeparator: { $0.isWhitespace }).map(String.init))
            }
        }

        let plain = stripLiteralBlocks(normalized)
            .replacingOccurrences(of: #"[=*/_'^|]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[([^\]|]*\|)?([^\]]*)\]\]"#, with: "$2", options: .regularExpression)
            .replacingOccurrences(of: #"\{\{[^}]*\}\}"#, with: " ", options: .regularExpression)
        let words = plain.split { $0.isWhitespace }.count
        let preview = plain
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.isEmpty == false && $0 != title }
            .map { String($0.prefix(220)) } ?? ""

        let links = linkIDs(in: normalized, fromNoteID: noteID, pagesBase: pagesBase)
            .map { pathWithoutExtension(forPageID: $0, pagesBase: pagesBase) }

        let paragraphs = plain.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .prefix(200)
            .map { RenderBlock.paragraph(text: .plain($0)) }

        var uniqueTags = [String]()
        for tag in tags where uniqueTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) == false {
            uniqueTags.append(tag)
        }

        return ObsidianParseResult(
            title: title ?? fallbackTitle,
            previewText: preview,
            frontmatter: NoteFrontmatter(),
            blocks: Array(paragraphs),
            outboundLinks: links,
            tags: uniqueTags,
            tableOfContents: toc,
            wordCount: words,
            readingTimeMinutes: max(1, Int(ceil(Double(words) / 220.0)))
        )
    }

    static func heading(in line: String) -> (level: Int, text: String)? {
        guard let match = line.range(of: #"^[ \t]*(={2,6})(.+?)(={2,6})[ \t]*$"#, options: .regularExpression) else {
            return nil
        }
        let content = String(line[match]).trimmingCharacters(in: .whitespaces)
        let leading = content.prefix(while: { $0 == "=" }).count
        let trailing = content.reversed().prefix(while: { $0 == "=" }).count
        let text = content.dropFirst(leading).dropLast(trailing).trimmingCharacters(in: .whitespaces)
        guard text.isEmpty == false else { return nil }
        return (max(1, 7 - min(leading, trailing)), text)
    }
}
