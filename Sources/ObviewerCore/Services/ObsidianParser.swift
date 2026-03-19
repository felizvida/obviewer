import Foundation

public struct ObsidianParseResult: Sendable {
    public let title: String
    public let previewText: String
    public let blocks: [RenderBlock]
    public let outboundLinks: [String]
    public let tags: [String]
    public let tableOfContents: [TableOfContentsItem]
    public let wordCount: Int
    public let readingTimeMinutes: Int
}

public struct ObsidianParser: Sendable {
    private let imageExtensions = Set(["png", "jpg", "jpeg", "gif", "webp", "heic"])

    public init() {}

    public func parse(markdown: String, fallbackTitle: String) -> ObsidianParseResult {
        let cleaned = stripFrontmatter(from: markdown)
        let lines = cleaned.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var blocks = [RenderBlock]()
        var outboundLinks = OrderedStringSet()
        var tags = OrderedStringSet()
        var tableOfContents = [TableOfContentsItem]()
        var anchorCounts = [String: Int]()
        var collectedParagraphLines = [String]()
        var collectedListItems = [String]()
        var title = fallbackTitle
        var index = 0

        func inline(_ raw: String) -> RichText {
            parseInline(raw, outboundLinks: &outboundLinks, tags: &tags)
        }

        func flushParagraph() {
            guard collectedParagraphLines.isEmpty == false else { return }
            let joined = collectedParagraphLines.joined(separator: " ")
            let transformed = inline(joined)
            if transformed.isEmpty == false {
                blocks.append(.paragraph(text: transformed))
            }
            collectedParagraphLines.removeAll(keepingCapacity: true)
        }

        func flushList() {
            guard collectedListItems.isEmpty == false else { return }
            let items = collectedListItems.map(inline).filter { $0.isEmpty == false }
            if items.isEmpty == false {
                blocks.append(.bulletList(items: items))
            }
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
                let transformed = inline(heading.text)
                if heading.level == 1, title == fallbackTitle, transformed.plainText.isEmpty == false {
                    title = transformed.plainText
                }

                let anchor = makeUniqueAnchor(from: transformed.plainText, counts: &anchorCounts)
                tableOfContents.append(
                    TableOfContentsItem(id: anchor, level: heading.level, title: transformed.plainText)
                )
                blocks.append(.heading(level: heading.level, text: transformed, anchor: anchor))
                index += 1
                continue
            }

            if let table = parseTable(
                from: lines,
                startIndex: index,
                outboundLinks: &outboundLinks,
                tags: &tags
            ) {
                flushParagraph()
                flushList()
                blocks.append(.table(headers: table.headers, rows: table.rows))
                index = table.nextIndex
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
                blocks.append(
                    .code(
                        language: language.isEmpty ? nil : language,
                        code: codeLines.joined(separator: "\n")
                    )
                )
                continue
            }

            if let callout = parseCallout(from: lines, startIndex: index) {
                flushParagraph()
                flushList()
                blocks.append(
                    .callout(
                        kind: callout.kind,
                        title: inline(callout.title),
                        body: inline(callout.body)
                    )
                )
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
                blocks.append(.quote(text: inline(quoteLines.joined(separator: " "))))
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
                return text.plainText
            case .heading(_, let text, _):
                return text.plainText
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
            tableOfContents: tableOfContents,
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
            let parsed = parseObsidianEmbedTarget(target)
            guard isImagePath(parsed.path) else { return nil }
            return (path: parsed.path, alt: parsed.alt)
        }

        let groups = matchGroups(in: line, pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#)
        guard groups.count == 2 else { return nil }
        let path = groups[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isImagePath(path) else { return nil }
        let alt = groups[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return (path: path, alt: alt.isEmpty ? nil : alt)
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

    private func parseTable(
        from lines: [String],
        startIndex: Int,
        outboundLinks: inout OrderedStringSet,
        tags: inout OrderedStringSet
    ) -> (headers: [RichText], rows: [[RichText]], nextIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }
        guard let headerCells = parseTableRow(from: lines[startIndex]) else { return nil }
        guard let separatorCells = parseTableRow(from: lines[startIndex + 1]) else { return nil }
        guard isTableSeparatorRow(separatorCells, expectedColumnCount: headerCells.count) else { return nil }

        var rows = [[RichText]]()
        var index = startIndex + 2

        while index < lines.count, let rowCells = parseTableRow(from: lines[index]) {
            rows.append(
                normalizeTableCells(rowCells, expectedColumnCount: headerCells.count).map {
                    parseInline($0, outboundLinks: &outboundLinks, tags: &tags)
                }
            )
            index += 1
        }

        return (
            headerCells.map { parseInline($0, outboundLinks: &outboundLinks, tags: &tags) },
            rows,
            index
        )
    }

    private func parseTableRow(from line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }

        var working = trimmed
        if working.hasPrefix("|") {
            working.removeFirst()
        }
        if working.hasSuffix("|") {
            working.removeLast()
        }

        let cells = working.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return cells.count >= 2 ? cells : nil
    }

    private func isTableSeparatorRow(_ cells: [String], expectedColumnCount: Int) -> Bool {
        guard cells.count == expectedColumnCount else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespaces)
            return stripped.isEmpty && cell.contains("-")
        }
    }

    private func normalizeTableCells(_ cells: [String], expectedColumnCount: Int) -> [String] {
        if cells.count == expectedColumnCount {
            return cells
        }

        if cells.count > expectedColumnCount {
            return Array(cells.prefix(expectedColumnCount))
        }

        return cells + Array(repeating: "", count: expectedColumnCount - cells.count)
    }

    private func parseInline(
        _ text: String,
        outboundLinks: inout OrderedStringSet,
        tags: inout OrderedStringSet
    ) -> RichText {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        var index = normalized.startIndex
        var runs = [InlineRun]()

        func appendText(_ value: String) {
            guard value.isEmpty == false else { return }
            if case .text(let existing)? = runs.last {
                runs[runs.count - 1] = .text(existing + value)
            } else {
                runs.append(.text(value))
            }
        }

        while index < normalized.endIndex {
            if normalized[index...].hasPrefix("![["),
               let close = normalized[index...].range(of: "]]") {
                let rawTarget = String(normalized[normalized.index(index, offsetBy: 3)..<close.lowerBound])
                let embedded = parseObsidianEmbedTarget(rawTarget)
                let destination = classifyLinkDestination(embedded.path)
                recordOutboundLink(destination, outboundLinks: &outboundLinks)
                runs.append(
                    .link(
                        label: inlineEmbedLabel(
                            for: embedded.path,
                            display: embedded.alt,
                            destination: destination
                        ),
                        destination: destination
                    )
                )
                index = close.upperBound
                continue
            }

            if normalized[index...].hasPrefix("[["),
               let close = normalized[index...].range(of: "]]") {
                let rawTarget = String(normalized[normalized.index(index, offsetBy: 2)..<close.lowerBound])
                let parts = rawTarget.split(separator: "|", maxSplits: 1).map(String.init)
                let targetPart = parts[0]
                let label = parts.count > 1 ? parts[1] : targetPart
                let destination = classifyLinkDestination(targetPart)
                recordOutboundLink(destination, outboundLinks: &outboundLinks)
                runs.append(.link(label: label, destination: destination))
                index = close.upperBound
                continue
            }

            if normalized[index...].hasPrefix("!["),
               let labelEnd = normalized[normalized.index(index, offsetBy: 2)...].firstIndex(of: "]") {
                let openParen = normalized.index(after: labelEnd)
                if openParen < normalized.endIndex, normalized[openParen] == "(" {
                    let destinationStart = normalized.index(after: openParen)
                    if let destinationEnd = normalized[destinationStart...].firstIndex(of: ")") {
                        let alt = String(normalized[normalized.index(index, offsetBy: 2)..<labelEnd])
                        let destinationValue = String(normalized[destinationStart..<destinationEnd])
                        let destination = classifyLinkDestination(destinationValue)
                        recordOutboundLink(destination, outboundLinks: &outboundLinks)
                        runs.append(
                            .link(
                                label: inlineEmbedLabel(
                                    for: destinationValue,
                                    display: alt,
                                    destination: destination
                                ),
                                destination: destination
                            )
                        )
                        index = normalized.index(after: destinationEnd)
                        continue
                    }
                }
            }

            if normalized[index] == "[",
               let labelEnd = normalized[normalized.index(after: index)...].firstIndex(of: "]") {
                let openParen = normalized.index(after: labelEnd)
                if openParen < normalized.endIndex, normalized[openParen] == "(" {
                    let destinationStart = normalized.index(after: openParen)
                    if let destinationEnd = normalized[destinationStart...].firstIndex(of: ")") {
                        let label = String(normalized[normalized.index(after: index)..<labelEnd])
                        let destination = String(normalized[destinationStart..<destinationEnd])
                        let resolvedDestination = classifyLinkDestination(destination)
                        recordOutboundLink(resolvedDestination, outboundLinks: &outboundLinks)
                        runs.append(.link(label: label, destination: resolvedDestination))
                        index = normalized.index(after: destinationEnd)
                        continue
                    }
                }
            }

            if normalized[index] == "`" {
                let codeStart = normalized.index(after: index)
                if let codeEnd = normalized[codeStart...].firstIndex(of: "`") {
                    runs.append(.code(String(normalized[codeStart..<codeEnd])))
                    index = normalized.index(after: codeEnd)
                    continue
                }
            }

            if normalized[index...].hasPrefix("**") {
                let strongStart = normalized.index(index, offsetBy: 2)
                if let strongEnd = normalized[strongStart...].range(of: "**") {
                    runs.append(.strong(String(normalized[strongStart..<strongEnd.lowerBound])))
                    index = strongEnd.upperBound
                    continue
                }
            }

            if normalized[index] == "*" {
                let emphasisStart = normalized.index(after: index)
                if let emphasisEnd = normalized[emphasisStart...].firstIndex(of: "*") {
                    runs.append(.emphasis(String(normalized[emphasisStart..<emphasisEnd])))
                    index = normalized.index(after: emphasisEnd)
                    continue
                }
            }

            if normalized[index] == "#", isTagBoundary(in: normalized, at: index) {
                let tagStart = normalized.index(after: index)
                var tagEnd = tagStart

                while tagEnd < normalized.endIndex {
                    let character = normalized[tagEnd]
                    if character.isLetter || character.isNumber || character == "_" || character == "/" || character == "-" {
                        tagEnd = normalized.index(after: tagEnd)
                    } else {
                        break
                    }
                }

                if tagEnd > tagStart {
                    let tag = String(normalized[tagStart..<tagEnd])
                    tags.append(tag)
                    runs.append(.tag(tag))
                    index = tagEnd
                    continue
                }
            }

            appendText(String(normalized[index]))
            index = normalized.index(after: index)
        }

        return RichText(runs: runs)
    }

    private func classifyLinkDestination(_ destination: String) -> LinkDestination {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered.contains("://") || lowered.hasPrefix("mailto:") {
            return .external(trimmed)
        }

        if trimmed.hasPrefix("#") {
            return .anchor(makeAnchorSlug(String(trimmed.dropFirst())))
        }

        let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let target = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let anchor = parts.count > 1 ? makeAnchorSlug(parts[1]) : nil
        let pathExtension = (target as NSString).pathExtension.lowercased()

        if pathExtension.isEmpty || pathExtension == "md" {
            return .note(target: target, anchor: anchor)
        }

        return .attachment(target)
    }

    private func isTagBoundary(in text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        return text[text.index(before: index)].isWhitespace
    }

    private func parseObsidianEmbedTarget(_ raw: String) -> (path: String, alt: String?) {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let path = parts[0]
        let displayValue = parts.count > 1 ? parts[1] : nil
        let alt = displayValue.flatMap { value in
            isDimensionSpecifier(value) ? nil : value
        }
        return (path: path, alt: alt)
    }

    private func inlineEmbedLabel(
        for path: String,
        display: String?,
        destination: LinkDestination
    ) -> String {
        let fallback = defaultDisplayLabel(for: path)
        let trimmedDisplay = display?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = trimmedDisplay.isEmpty ? fallback : trimmedDisplay

        switch destination {
        case .attachment(let attachmentPath):
            return isImagePath(attachmentPath)
                ? "[Image: \(label)]"
                : "[Attachment: \(label)]"
        case .note:
            return "[Embed: \(label)]"
        case .anchor:
            return "[Section: \(label)]"
        case .external:
            return "[Embed: \(label)]"
        }
    }

    private func defaultDisplayLabel(for path: String) -> String {
        let target = path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
        let basename = (target as NSString).lastPathComponent
        return basename.isEmpty ? target : basename
    }

    private func isDimensionSpecifier(_ value: String) -> Bool {
        matchFirst(in: value, pattern: #"^\d+(x\d+)?$"#) != nil
    }

    private func isImagePath(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    private func recordOutboundLink(
        _ destination: LinkDestination,
        outboundLinks: inout OrderedStringSet
    ) {
        if case .note(let target, _) = destination, target.isEmpty == false {
            outboundLinks.append(target)
        }
    }

    private func makeUniqueAnchor(from title: String, counts: inout [String: Int]) -> String {
        let slug = makeAnchorSlug(title)
        let nextCount = counts[slug, default: 0]
        counts[slug] = nextCount + 1
        return nextCount == 0 ? slug : "\(slug)-\(nextCount + 1)"
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
