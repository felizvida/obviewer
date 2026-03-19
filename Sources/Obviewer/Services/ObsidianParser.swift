import Foundation

struct ObsidianParseResult: Sendable {
    let title: String
    let previewText: String
    let blocks: [RenderBlock]
    let outboundLinks: [String]
    let tags: [String]
    let wordCount: Int
    let readingTimeMinutes: Int
}

struct ObsidianParser: Sendable {
    func parse(markdown: String, fallbackTitle: String) -> ObsidianParseResult {
        let cleaned = stripFrontmatter(from: markdown)
        let lines = cleaned.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var blocks = [RenderBlock]()
        var outboundLinks = OrderedStringSet()
        var tags = OrderedStringSet()
        var collectedParagraphLines = [String]()
        var collectedListItems = [String]()
        var title = fallbackTitle
        var index = 0

        func flushParagraph() {
            guard collectedParagraphLines.isEmpty == false else { return }
            let joined = collectedParagraphLines.joined(separator: " ")
            let transformed = transformInline(joined, outboundLinks: &outboundLinks, tags: &tags)
            blocks.append(.paragraph(text: transformed))
            collectedParagraphLines.removeAll(keepingCapacity: true)
        }

        func flushList() {
            guard collectedListItems.isEmpty == false else { return }
            let items = collectedListItems.map {
                transformInline($0, outboundLinks: &outboundLinks, tags: &tags)
            }
            blocks.append(.bulletList(items: items))
            collectedListItems.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                index += 1
                continue
            }

            if let heading = parseHeading(from: trimmed) {
                flushParagraph()
                flushList()
                let transformed = transformInline(heading.text, outboundLinks: &outboundLinks, tags: &tags)
                if heading.level == 1, title == fallbackTitle {
                    title = transformed
                }
                blocks.append(.heading(level: heading.level, text: transformed))
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                flushList()
                blocks.append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushList()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines = [String]()
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces) != "```" {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language, code: codeLines.joined(separator: "\n")))
                continue
            }

            if let callout = parseCallout(from: lines, startIndex: index) {
                flushParagraph()
                flushList()
                let title = transformInline(callout.title, outboundLinks: &outboundLinks, tags: &tags)
                let body = transformInline(callout.body, outboundLinks: &outboundLinks, tags: &tags)
                blocks.append(.callout(kind: callout.kind, title: title, body: body))
                index = callout.nextIndex
                continue
            }

            if let image = parseStandaloneImage(from: trimmed) {
                flushParagraph()
                flushList()
                blocks.append(.image(path: image.path, alt: image.alt))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                var quoteLines = [String]()
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    let content = candidate.dropFirst().trimmingCharacters(in: .whitespaces)
                    quoteLines.append(String(content))
                    index += 1
                }
                let transformed = transformInline(quoteLines.joined(separator: " "), outboundLinks: &outboundLinks, tags: &tags)
                blocks.append(.quote(text: transformed))
                continue
            }

            if let listItem = parseListItem(from: trimmed) {
                flushParagraph()
                collectedListItems.append(listItem)
                index += 1
                continue
            }

            collectedParagraphLines.append(trimmed)
            index += 1
        }

        flushParagraph()
        flushList()

        let previewText = blocks.compactMap { block -> String? in
            switch block {
            case .paragraph(let text):
                return text
            case .heading(_, let text):
                return text
            default:
                return nil
            }
        }.first ?? fallbackTitle

        let wordCount = countWords(in: cleaned)
        return ObsidianParseResult(
            title: title,
            previewText: previewText,
            blocks: blocks,
            outboundLinks: outboundLinks.values,
            tags: tags.values,
            wordCount: wordCount,
            readingTimeMinutes: max(1, Int(ceil(Double(wordCount) / 220.0)))
        )
    }

    private func stripFrontmatter(from markdown: String) -> String {
        guard markdown.hasPrefix("---\n") else { return markdown }
        let remainder = markdown.dropFirst(4)
        guard let closingRange = remainder.range(of: "\n---\n") else { return markdown }
        return String(remainder[closingRange.upperBound...])
    }

    private func parseHeading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard hashes.isEmpty == false, hashes.count <= 6 else { return nil }
        let text = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard text.isEmpty == false else { return nil }
        return (hashes.count, text)
    }

    private func parseListItem(from line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private func parseStandaloneImage(from line: String) -> (path: String, alt: String?)? {
        if let target = matchFirst(in: line, pattern: #"^!\[\[([^\]]+)\]\]$"#) {
            return (path: target, alt: nil)
        }

        let groups = matchGroups(in: line, pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#)
        guard groups.count == 2 else { return nil }
        let alt = groups[0].isEmpty ? nil : groups[0]
        return (path: groups[1], alt: alt)
    }

    private func parseCallout(from lines: [String], startIndex: Int) -> (kind: CalloutKind, title: String, body: String, nextIndex: Int)? {
        let line = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let groups = matchGroups(in: line, pattern: #"^>\s*\[!([A-Za-z]+)\]\s*(.*)$"#)
        guard groups.count == 2 else { return nil }

        let kind = CalloutKind(rawValue: groups[0].lowercased()) ?? .note
        var collected = [String]()
        let title = groups[1].isEmpty ? kind.label : groups[1]
        var index = startIndex + 1

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            collected.append(String(content))
            index += 1
        }

        return (kind, title, collected.joined(separator: " "), index)
    }

    private func transformInline(
        _ text: String,
        outboundLinks: inout OrderedStringSet,
        tags: inout OrderedStringSet
    ) -> String {
        var output = text

        for imageLink in matchGroupsCollection(in: output, pattern: #"!\[\[([^\]]+)\]\]"#) {
            guard let path = imageLink.first else { continue }
            output = output.replacingOccurrences(of: "![[\(path)]]", with: "")
        }

        for link in matchGroupsCollection(in: output, pattern: #"\[\[([^\]]+)\]\]"#) {
            guard let rawTarget = link.first else { continue }
            let parts = rawTarget.split(separator: "|", maxSplits: 1).map(String.init)
            let targetPart = parts[0]
            let visibleText = parts.count > 1 ? parts[1] : targetPart
            let target = targetPart.split(separator: "#", maxSplits: 1).first.map(String.init) ?? targetPart
            outboundLinks.append(target)
            output = output.replacingOccurrences(of: "[[\(rawTarget)]]", with: visibleText)
        }

        for tag in matchGroupsCollection(in: output, pattern: #"(?:(?<=\s)|^)#([A-Za-z0-9_/\-]+)"#) {
            guard let value = tag.first else { continue }
            tags.append(value)
        }

        output = output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func countWords(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func matchFirst(in input: String, pattern: String) -> String? {
        matchGroups(in: input, pattern: pattern).first
    }

    private func matchGroups(in input: String, pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = expression.firstMatch(in: input, range: range) else {
            return []
        }

        return (1..<match.numberOfRanges).compactMap { index in
            let matchRange = match.range(at: index)
            guard let swiftRange = Range(matchRange, in: input) else { return nil }
            return String(input[swiftRange])
        }
    }

    private func matchGroupsCollection(in input: String, pattern: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return expression.matches(in: input, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                let matchRange = match.range(at: index)
                guard let swiftRange = Range(matchRange, in: input) else { return nil }
                return String(input[swiftRange])
            }
        }
    }
}

private struct OrderedStringSet: Sendable {
    private(set) var values = [String]()
    private var seen = Set<String>()

    mutating func append(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return }
        let key = normalized.lowercased()
        guard seen.insert(key).inserted else { return }
        values.append(normalized)
    }
}
