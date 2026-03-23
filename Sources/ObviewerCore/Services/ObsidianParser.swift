import Foundation

public struct ObsidianParseResult: Sendable {
    public let title: String
    public let previewText: String
    public let frontmatter: NoteFrontmatter
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
        let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let extraction = extractFrontmatter(from: normalizedMarkdown)
        let cleaned = extraction.body
        let frontmatter = extraction.frontmatter
        let lines = cleaned.components(separatedBy: "\n")

        var blocks = [RenderBlock]()
        var outboundLinks = OrderedStringSet()
        var tags = OrderedStringSet()
        var tableOfContents = [TableOfContentsItem]()
        var anchorCounts = [String: Int]()
        var collectedParagraphLines = [String]()
        var footnoteDefinitions = [ParsedFootnoteDefinition]()
        var title = fallbackTitle
        let frontmatterTitle = frontmatter.value(for: "title")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        var index = 0

        for tag in frontmatter.tags {
            tags.append(tag)
        }

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

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let footnote = parseFootnoteDefinition(
                from: lines,
                startIndex: index
            ) {
                flushParagraph()
                footnoteDefinitions.append(footnote)
                index = footnote.nextIndex
                continue
            }

            if let heading = parseHeading(from: trimmed) {
                flushParagraph()
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
                blocks.append(.table(headers: table.headers, rows: table.rows))
                index = table.nextIndex
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
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
                let code = codeLines.joined(separator: "\n")
                if let unsupportedBlock = unsupportedFenceBlock(language: language, code: code) {
                    blocks.append(.unsupported(unsupportedBlock))
                } else {
                    blocks.append(
                        .code(
                            language: language.isEmpty ? nil : language,
                            code: code
                        )
                    )
                }
                continue
            }

            if let callout = parseCallout(from: lines, startIndex: index) {
                flushParagraph()
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
                blocks.append(.image(path: image.path, alt: image.alt, sizeHint: image.sizeHint))
                index += 1
                continue
            }

            if let unsupportedEmbed = parseStandaloneUnsupportedEmbed(from: trimmed) {
                flushParagraph()
                blocks.append(.unsupported(unsupportedEmbed))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
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

            if let list = parseList(
                from: lines,
                startIndex: index,
                outboundLinks: &outboundLinks,
                tags: &tags
            ) {
                flushParagraph()
                blocks.append(.list(items: list.items))
                index = list.nextIndex
                continue
            }

            collectedParagraphLines.append(trimmed)
            index += 1
        }

        flushParagraph()

        if footnoteDefinitions.isEmpty == false {
            blocks.append(
                .footnotes(
                    items: footnoteDefinitions.map { definition in
                        FootnoteItem(
                            id: footnoteAnchorID(for: definition.label),
                            label: definition.label,
                            text: inline(definition.body)
                        )
                    }
                )
            )
        }

        if title == fallbackTitle, let frontmatterTitle, frontmatterTitle.isEmpty == false {
            title = frontmatterTitle
        }

        let previewText = blocks.compactMap { block -> String? in
            switch block {
            case .paragraph(let text):
                return text.plainText
            case .heading(_, let text, _):
                return text.plainText
            default:
                return nil
            }
        }.first ?? title

        let wordCount = countWords(in: cleaned)
        return ObsidianParseResult(
            title: title,
            previewText: previewText,
            frontmatter: frontmatter,
            blocks: blocks,
            outboundLinks: outboundLinks.values,
            tags: tags.values,
            tableOfContents: tableOfContents,
            wordCount: wordCount,
            readingTimeMinutes: max(1, Int(ceil(Double(wordCount) / 220.0)))
        )
    }

    private func extractFrontmatter(from markdown: String) -> (frontmatter: NoteFrontmatter, body: String) {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---" else {
            return (NoteFrontmatter(), markdown)
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else {
            return (NoteFrontmatter(), markdown)
        }

        let frontmatterLines = Array(lines[1..<closingIndex])
        let bodyLines = closingIndex < lines.count - 1
            ? Array(lines[(closingIndex + 1)...])
            : []
        return (
            parseFrontmatter(from: frontmatterLines),
            bodyLines.joined(separator: "\n")
        )
    }

    private func parseHeading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard hashes.isEmpty == false, hashes.count <= 6 else { return nil }
        let text = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard text.isEmpty == false else { return nil }
        return (hashes.count, text)
    }

    private func parseFootnoteDefinition(
        from lines: [String],
        startIndex: Int
    ) -> ParsedFootnoteDefinition? {
        let line = lines[startIndex]
        let groups = matchGroups(in: line, pattern: #"^\[\^([^\]]+)\]:\s*(.*)$"#)
        guard groups.count == 2 else {
            return nil
        }

        var bodyLines = [groups[1]]
        var index = startIndex + 1

        while index < lines.count {
            let candidate = lines[index]
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            let indent = indentationLevel(of: candidate)
            guard indent > 0 else {
                break
            }

            bodyLines.append(String(candidate.dropFirst(indent)).trimmingCharacters(in: .whitespacesAndNewlines))
            index += 1
        }

        return ParsedFootnoteDefinition(
            label: groups[0],
            body: bodyLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .joined(separator: " "),
            nextIndex: index
        )
    }

    private func footnoteAnchorID(for label: String) -> String {
        "footnote-\(makeAnchorSlug(label))"
    }

    private func unsupportedFenceBlock(language: String, code: String) -> UnsupportedBlock? {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedLanguage.isEmpty == false else {
            return nil
        }

        switch normalizedLanguage {
        case "mermaid":
            return UnsupportedBlock(
                title: "Mermaid Diagram Preview Unavailable",
                body: code.isEmpty ? "This note contains a Mermaid block that is not rendered yet." : code
            )
        case "math", "latex", "katex":
            return UnsupportedBlock(
                title: "Math Block Preview Unavailable",
                body: code.isEmpty ? "This note contains a math block that is not rendered yet." : code
            )
        default:
            return nil
        }
    }

    private func parseStandaloneUnsupportedEmbed(from line: String) -> UnsupportedBlock? {
        guard let target = matchFirst(in: line, pattern: #"^!\[\[([^\]]+)\]\]$"#) else {
            return nil
        }

        let parsed = parseObsidianEmbedTarget(target)
        let destination = classifyLinkDestination(parsed.path)

        guard case .attachment(let attachmentPath) = destination, isImagePath(attachmentPath) == false else {
            return nil
        }

        let label = parsed.alt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLabel = (label?.isEmpty == false ? label : defaultDisplayLabel(for: attachmentPath)) ?? attachmentPath
        let extensionName = (attachmentPath as NSString).pathExtension.lowercased()

        let title: String
        switch extensionName {
        case "pdf":
            title = "Embedded PDF Preview Unavailable"
        case "mp3", "m4a", "wav":
            title = "Embedded Audio Preview Unavailable"
        case "mp4", "mov":
            title = "Embedded Video Preview Unavailable"
        default:
            title = "Embedded Attachment Preview Unavailable"
        }

        return UnsupportedBlock(
            title: title,
            body: displayLabel,
            attachmentPath: attachmentPath
        )
    }

    private func parseFrontmatter(from lines: [String]) -> NoteFrontmatter {
        var entries = [FrontmatterEntry]()
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }

            guard let separatorIndex = line.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else {
                index += 1
                continue
            }

            let inlineValue = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            index += 1

            if inlineValue.isEmpty == false {
                entries.append(
                    FrontmatterEntry(
                        key: key,
                        value: parseFrontmatterValue(inlineValue)
                    )
                )
                continue
            }

            var blockLines = [String]()
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                if candidateTrimmed.isEmpty {
                    index += 1
                    continue
                }

                let indent = indentationLevel(of: candidate)
                guard indent > 0 else {
                    break
                }

                blockLines.append(String(candidate.dropFirst(indent)))
                index += 1
            }

            guard blockLines.isEmpty == false else {
                entries.append(
                    FrontmatterEntry(
                        key: key,
                        value: .string("")
                    )
                )
                continue
            }

            entries.append(
                FrontmatterEntry(
                    key: key,
                    value: parseFrontmatterBlockValue(blockLines)
                )
            )
        }

        return NoteFrontmatter(entries: entries)
    }

    private func parseFrontmatterBlockValue(_ lines: [String]) -> FrontmatterValue {
        let meaningfulLines = lines.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        guard meaningfulLines.isEmpty == false else {
            return .string("")
        }

        if meaningfulLines.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("- ") }) {
            let values = meaningfulLines.map { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                return parseFrontmatterScalar(value)
            }
            return .array(values)
        }

        return .string(
            meaningfulLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
        )
    }

    private func parseFrontmatterValue(_ rawValue: String) -> FrontmatterValue {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .string("")
        }

        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let content = String(trimmed.dropFirst().dropLast())
            let values = splitInlineFrontmatterArray(content).map(parseFrontmatterScalar)
            return .array(values)
        }

        return parseFrontmatterScalar(trimmed)
    }

    private func parseFrontmatterScalar(_ rawValue: String) -> FrontmatterValue {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted = unquoteFrontmatterValue(trimmed)
        let lowered = unquoted.lowercased()

        if lowered == "true" {
            return .bool(true)
        }
        if lowered == "false" {
            return .bool(false)
        }
        if let integer = Int(unquoted) {
            return .number(Double(integer))
        }
        if let number = Double(unquoted) {
            return .number(number)
        }

        return .string(unquoted)
    }

    private func splitInlineFrontmatterArray(_ value: String) -> [String] {
        var items = [String]()
        var current = ""
        var activeQuote: Character?

        for character in value {
            if activeQuote != nil {
                current.append(character)
                if character == activeQuote {
                    activeQuote = nil
                }
                continue
            }

            switch character {
            case "\"", "'":
                activeQuote = character
                current.append(character)
            case ",":
                items.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
            default:
                current.append(character)
            }
        }

        let final = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if final.isEmpty == false {
            items.append(final)
        }

        return items
    }

    private func unquoteFrontmatterValue(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }

        return value
    }

    private func parseList(
        from lines: [String],
        startIndex: Int,
        outboundLinks: inout OrderedStringSet,
        tags: inout OrderedStringSet
    ) -> (items: [RenderListItem], nextIndex: Int)? {
        guard let parsed = parseListItems(from: lines, startIndex: startIndex, expectedIndent: nil) else {
            return nil
        }

        let items = parsed.items.compactMap { item in
            makeRenderListItem(item, outboundLinks: &outboundLinks, tags: &tags)
        }
        guard items.isEmpty == false else {
            return nil
        }

        return (items, parsed.nextIndex)
    }

    private func parseStandaloneImage(from line: String) -> (path: String, alt: String?, sizeHint: ImageSizeHint?)? {
        if let target = matchFirst(in: line, pattern: #"^!\[\[([^\]]+)\]\]$"#) {
            let parsed = parseObsidianEmbedTarget(target)
            guard isImagePath(parsed.path) else { return nil }
            return (path: parsed.path, alt: parsed.alt, sizeHint: parsed.sizeHint)
        }

        let groups = matchGroups(in: line, pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#)
        guard groups.count == 2 else { return nil }
        let path = groups[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isImagePath(path) else { return nil }
        let alt = groups[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return (path: path, alt: alt.isEmpty ? nil : alt, sizeHint: nil)
    }

    private func parseListItems(
        from lines: [String],
        startIndex: Int,
        expectedIndent: Int?
    ) -> (items: [ParsedListItem], nextIndex: Int)? {
        guard startIndex < lines.count,
              let firstMarker = parseListMarker(from: lines[startIndex]) else {
            return nil
        }

        let baseIndent = expectedIndent ?? firstMarker.indent
        guard firstMarker.indent == baseIndent else {
            return nil
        }

        var items = [ParsedListItem]()
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard trimmed.isEmpty == false else {
                break
            }

            guard let marker = parseListMarker(from: line) else {
                if items.isEmpty == false, indentationLevel(of: line) > baseIndent {
                    items[items.count - 1].textLines.append(trimmed)
                    index += 1
                    continue
                }
                break
            }

            if marker.indent < baseIndent {
                break
            }

            if marker.indent > baseIndent {
                guard items.isEmpty == false,
                      let nested = parseListItems(
                        from: lines,
                        startIndex: index,
                        expectedIndent: marker.indent
                      ) else {
                    break
                }
                items[items.count - 1].children.append(contentsOf: nested.items)
                index = nested.nextIndex
                continue
            }

            var item = ParsedListItem(marker: marker.marker, textLines: [marker.text], children: [])
            index += 1

            while index < lines.count {
                let nextLine = lines[index]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)

                if nextTrimmed.isEmpty {
                    break
                }

                if let nestedMarker = parseListMarker(from: nextLine) {
                    if nestedMarker.indent < baseIndent {
                        break
                    }

                    if nestedMarker.indent == baseIndent {
                        break
                    }

                    guard let nested = parseListItems(
                        from: lines,
                        startIndex: index,
                        expectedIndent: nestedMarker.indent
                    ) else {
                        break
                    }
                    item.children.append(contentsOf: nested.items)
                    index = nested.nextIndex
                    continue
                }

                if indentationLevel(of: nextLine) > baseIndent {
                    item.textLines.append(nextTrimmed)
                    index += 1
                    continue
                }

                break
            }

            items.append(item)
        }

        guard items.isEmpty == false else {
            return nil
        }

        return (items, index)
    }

    private func parseListMarker(from line: String) -> ParsedListMarker? {
        let indent = indentationLevel(of: line)
        let stripped = line.drop(while: { $0 == " " || $0 == "\t" })
        let normalized = String(stripped)

        let taskGroups = matchGroups(in: normalized, pattern: #"^([-+*])\s+\[([ xX])\]\s+(.*)$"#)
        if taskGroups.count == 3 {
            return ParsedListMarker(
                indent: indent,
                marker: .task(isCompleted: taskGroups[1].lowercased() == "x"),
                text: taskGroups[2]
            )
        }

        let unorderedGroups = matchGroups(in: normalized, pattern: #"^([-+*])\s+(.*)$"#)
        if unorderedGroups.count == 2 {
            return ParsedListMarker(
                indent: indent,
                marker: .unordered,
                text: unorderedGroups[1]
            )
        }

        let orderedGroups = matchGroups(in: normalized, pattern: #"^(\d+)[\.\)]\s+(.*)$"#)
        if orderedGroups.count == 2, let number = Int(orderedGroups[0]) {
            return ParsedListMarker(
                indent: indent,
                marker: .ordered(number),
                text: orderedGroups[1]
            )
        }

        return nil
    }

    private func indentationLevel(of line: String) -> Int {
        var indent = 0
        for character in line {
            switch character {
            case " ":
                indent += 1
            case "\t":
                indent += 4
            default:
                return indent
            }
        }
        return indent
    }

    private func makeRenderListItem(
        _ item: ParsedListItem,
        outboundLinks: inout OrderedStringSet,
        tags: inout OrderedStringSet
    ) -> RenderListItem? {
        let text = parseInline(item.textLines.joined(separator: " "), outboundLinks: &outboundLinks, tags: &tags)
        let children = item.children.compactMap { child in
            makeRenderListItem(child, outboundLinks: &outboundLinks, tags: &tags)
        }

        guard text.isEmpty == false || children.isEmpty == false else {
            return nil
        }

        return RenderListItem(marker: item.marker, text: text, children: children)
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
                if case .attachment(let attachmentPath) = destination, isImagePath(attachmentPath) {
                    runs.append(.image(path: embedded.path, alt: embedded.alt, sizeHint: embedded.sizeHint))
                } else {
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
                }
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
                        if case .attachment(let attachmentPath) = destination, isImagePath(attachmentPath) {
                            let trimmedAlt = alt.trimmingCharacters(in: .whitespacesAndNewlines)
                            runs.append(
                                .image(
                                    path: destinationValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                    alt: trimmedAlt.isEmpty ? nil : trimmedAlt,
                                    sizeHint: nil
                                )
                            )
                        } else {
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
                        }
                        index = normalized.index(after: destinationEnd)
                        continue
                    }
                }
            }

            if normalized[index...].hasPrefix("[^"),
               let referenceEnd = normalized[normalized.index(index, offsetBy: 2)...].firstIndex(of: "]") {
                let label = String(normalized[normalized.index(index, offsetBy: 2)..<referenceEnd])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if label.isEmpty == false {
                    runs.append(
                        .link(
                            label: "[\(label)]",
                            destination: .anchor(footnoteAnchorID(for: label))
                        )
                    )
                    index = normalized.index(after: referenceEnd)
                    continue
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

    private func parseObsidianEmbedTarget(_ raw: String) -> (path: String, alt: String?, sizeHint: ImageSizeHint?) {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let path = parts[0]
        let displayValue = parts.count > 1 ? parts[1] : nil
        let sizeHint = displayValue.flatMap(parseImageSizeHint)
        let alt = displayValue.flatMap { value in
            sizeHint == nil ? value : nil
        }
        return (path: path, alt: alt, sizeHint: sizeHint)
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

    private func parseImageSizeHint(_ value: String) -> ImageSizeHint? {
        let groups = matchGroups(in: value, pattern: #"^(\d+)(?:x(\d+))?$"#)
        guard groups.isEmpty == false else { return nil }

        let width = Double(groups[0])
        let height = groups.count > 1 ? Double(groups[1]) : nil
        guard width != nil || height != nil else { return nil }
        return ImageSizeHint(width: width, height: height)
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

private struct ParsedListItem {
    let marker: RenderListMarker
    var textLines: [String]
    var children: [ParsedListItem]
}

private struct ParsedListMarker {
    let indent: Int
    let marker: RenderListMarker
    let text: String
}

private struct ParsedFootnoteDefinition {
    let label: String
    let body: String
    let nextIndex: Int
}
