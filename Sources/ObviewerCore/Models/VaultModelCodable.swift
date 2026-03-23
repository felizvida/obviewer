import Foundation

extension CalloutKind: Codable {}

extension NoteFrontmatter: Codable {
    private enum CodingKeys: String, CodingKey {
        case entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try container.decode([FrontmatterEntry].self, forKey: .entries))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
    }
}

extension FrontmatterEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case key
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try container.decode(String.self, forKey: .key),
            value: try container.decode(FrontmatterValue.self, forKey: .value)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(value, forKey: .value)
    }
}

extension VaultNote: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case relativePath
        case folderPath
        case previewText
        case frontmatter
        case tags
        case outboundLinks
        case tableOfContents
        case blocks
        case wordCount
        case readingTimeMinutes
        case modifiedAt
        case searchCorpus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            relativePath: try container.decode(String.self, forKey: .relativePath),
            folderPath: try container.decode(String.self, forKey: .folderPath),
            previewText: try container.decode(String.self, forKey: .previewText),
            frontmatter: try container.decode(NoteFrontmatter.self, forKey: .frontmatter),
            tags: try container.decode([String].self, forKey: .tags),
            outboundLinks: try container.decode([String].self, forKey: .outboundLinks),
            tableOfContents: try container.decode([TableOfContentsItem].self, forKey: .tableOfContents),
            blocks: try container.decode([RenderBlock].self, forKey: .blocks),
            wordCount: try container.decode(Int.self, forKey: .wordCount),
            readingTimeMinutes: try container.decode(Int.self, forKey: .readingTimeMinutes),
            modifiedAt: try container.decode(Date.self, forKey: .modifiedAt),
            searchCorpus: try container.decodeIfPresent(String.self, forKey: .searchCorpus)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(folderPath, forKey: .folderPath)
        try container.encode(previewText, forKey: .previewText)
        try container.encode(frontmatter, forKey: .frontmatter)
        try container.encode(tags, forKey: .tags)
        try container.encode(outboundLinks, forKey: .outboundLinks)
        try container.encode(tableOfContents, forKey: .tableOfContents)
        try container.encode(blocks, forKey: .blocks)
        try container.encode(wordCount, forKey: .wordCount)
        try container.encode(readingTimeMinutes, forKey: .readingTimeMinutes)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(searchCorpus, forKey: .searchCorpus)
    }
}

extension VaultAttachment.Kind: Codable {}

extension VaultAttachment: Codable {
    private enum CodingKeys: String, CodingKey {
        case relativePath
        case url
        case kind
        case modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            relativePath: try container.decode(String.self, forKey: .relativePath),
            url: try container.decode(URL.self, forKey: .url),
            kind: try container.decode(VaultAttachment.Kind.self, forKey: .kind),
            modifiedAt: try container.decode(Date.self, forKey: .modifiedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(url, forKey: .url)
        try container.encode(kind, forKey: .kind)
        try container.encode(modifiedAt, forKey: .modifiedAt)
    }
}

extension UnsupportedBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case title
        case body
        case attachmentPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try container.decode(String.self, forKey: .title),
            body: try container.decode(String.self, forKey: .body),
            attachmentPath: try container.decodeIfPresent(String.self, forKey: .attachmentPath)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(attachmentPath, forKey: .attachmentPath)
    }
}

extension FootnoteItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            label: try container.decode(String.self, forKey: .label),
            text: try container.decode(RichText.self, forKey: .text)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(text, forKey: .text)
    }
}

extension RenderListItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case marker
        case text
        case children
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            marker: try container.decode(RenderListMarker.self, forKey: .marker),
            text: try container.decode(RichText.self, forKey: .text),
            children: try container.decode([RenderListItem].self, forKey: .children)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(marker, forKey: .marker)
        try container.encode(text, forKey: .text)
        try container.encode(children, forKey: .children)
    }
}

extension ImageSizeHint: Codable {
    private enum CodingKeys: String, CodingKey {
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            width: try container.decodeIfPresent(Double.self, forKey: .width),
            height: try container.decodeIfPresent(Double.self, forKey: .height)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
    }
}

extension TableOfContentsItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case level
        case title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            level: try container.decode(Int.self, forKey: .level),
            title: try container.decode(String.self, forKey: .title)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(level, forKey: .level)
        try container.encode(title, forKey: .title)
    }
}

extension RichText: Codable {
    private enum CodingKeys: String, CodingKey {
        case runs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(runs: try container.decode([InlineRun].self, forKey: .runs))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runs, forKey: .runs)
    }
}

extension FrontmatterValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case stringValue
        case numberValue
        case boolValue
        case arrayValue
    }

    private enum Kind: String, Codable {
        case string
        case number
        case bool
        case array
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .string:
            self = .string(try container.decode(String.self, forKey: .stringValue))
        case .number:
            self = .number(try container.decode(Double.self, forKey: .numberValue))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .boolValue))
        case .array:
            self = .array(try container.decode([FrontmatterValue].self, forKey: .arrayValue))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .stringValue)
        case .number(let value):
            try container.encode(Kind.number, forKey: .kind)
            try container.encode(value, forKey: .numberValue)
        case .bool(let value):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(value, forKey: .boolValue)
        case .array(let values):
            try container.encode(Kind.array, forKey: .kind)
            try container.encode(values, forKey: .arrayValue)
        }
    }
}

extension RenderListMarker: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case startIndex
        case isCompleted
    }

    private enum Kind: String, Codable {
        case unordered
        case ordered
        case task
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .unordered:
            self = .unordered
        case .ordered:
            self = .ordered(try container.decode(Int.self, forKey: .startIndex))
        case .task:
            self = .task(isCompleted: try container.decode(Bool.self, forKey: .isCompleted))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unordered:
            try container.encode(Kind.unordered, forKey: .kind)
        case .ordered(let value):
            try container.encode(Kind.ordered, forKey: .kind)
            try container.encode(value, forKey: .startIndex)
        case .task(let isCompleted):
            try container.encode(Kind.task, forKey: .kind)
            try container.encode(isCompleted, forKey: .isCompleted)
        }
    }
}

extension LinkDestination: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case target
        case anchor
        case path
        case externalURL
    }

    private enum Kind: String, Codable {
        case note
        case anchor
        case attachment
        case external
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .note:
            self = .note(
                target: try container.decode(String.self, forKey: .target),
                anchor: try container.decodeIfPresent(String.self, forKey: .anchor)
            )
        case .anchor:
            self = .anchor(try container.decode(String.self, forKey: .anchor))
        case .attachment:
            self = .attachment(try container.decode(String.self, forKey: .path))
        case .external:
            self = .external(try container.decode(String.self, forKey: .externalURL))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .note(let target, let anchor):
            try container.encode(Kind.note, forKey: .kind)
            try container.encode(target, forKey: .target)
            try container.encodeIfPresent(anchor, forKey: .anchor)
        case .anchor(let value):
            try container.encode(Kind.anchor, forKey: .kind)
            try container.encode(value, forKey: .anchor)
        case .attachment(let value):
            try container.encode(Kind.attachment, forKey: .kind)
            try container.encode(value, forKey: .path)
        case .external(let value):
            try container.encode(Kind.external, forKey: .kind)
            try container.encode(value, forKey: .externalURL)
        }
    }
}

extension InlineRun: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case label
        case destination
        case path
        case alt
        case sizeHint
        case tag
    }

    private enum Kind: String, Codable {
        case text
        case strong
        case emphasis
        case code
        case link
        case image
        case tag
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .strong:
            self = .strong(try container.decode(String.self, forKey: .text))
        case .emphasis:
            self = .emphasis(try container.decode(String.self, forKey: .text))
        case .code:
            self = .code(try container.decode(String.self, forKey: .text))
        case .link:
            self = .link(
                label: try container.decode(String.self, forKey: .label),
                destination: try container.decode(LinkDestination.self, forKey: .destination)
            )
        case .image:
            self = .image(
                path: try container.decode(String.self, forKey: .path),
                alt: try container.decodeIfPresent(String.self, forKey: .alt),
                sizeHint: try container.decodeIfPresent(ImageSizeHint.self, forKey: .sizeHint)
            )
        case .tag:
            self = .tag(try container.decode(String.self, forKey: .tag))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .strong(let value):
            try container.encode(Kind.strong, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .emphasis(let value):
            try container.encode(Kind.emphasis, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .code(let value):
            try container.encode(Kind.code, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .link(let label, let destination):
            try container.encode(Kind.link, forKey: .kind)
            try container.encode(label, forKey: .label)
            try container.encode(destination, forKey: .destination)
        case .image(let path, let alt, let sizeHint):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(alt, forKey: .alt)
            try container.encodeIfPresent(sizeHint, forKey: .sizeHint)
        case .tag(let value):
            try container.encode(Kind.tag, forKey: .kind)
            try container.encode(value, forKey: .tag)
        }
    }
}

extension RenderBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case level
        case text
        case anchor
        case items
        case calloutKind
        case title
        case body
        case headers
        case rows
        case language
        case code
        case path
        case alt
        case sizeHint
        case unsupported
        case footnotes
    }

    private enum Kind: String, Codable {
        case heading
        case paragraph
        case list
        case quote
        case callout
        case table
        case code
        case image
        case unsupported
        case footnotes
        case divider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .heading:
            self = .heading(
                level: try container.decode(Int.self, forKey: .level),
                text: try container.decode(RichText.self, forKey: .text),
                anchor: try container.decode(String.self, forKey: .anchor)
            )
        case .paragraph:
            self = .paragraph(text: try container.decode(RichText.self, forKey: .text))
        case .list:
            self = .list(items: try container.decode([RenderListItem].self, forKey: .items))
        case .quote:
            self = .quote(text: try container.decode(RichText.self, forKey: .text))
        case .callout:
            self = .callout(
                kind: try container.decode(CalloutKind.self, forKey: .calloutKind),
                title: try container.decode(RichText.self, forKey: .title),
                body: try container.decode(RichText.self, forKey: .body)
            )
        case .table:
            self = .table(
                headers: try container.decode([RichText].self, forKey: .headers),
                rows: try container.decode([[RichText]].self, forKey: .rows)
            )
        case .code:
            self = .code(
                language: try container.decodeIfPresent(String.self, forKey: .language),
                code: try container.decode(String.self, forKey: .code)
            )
        case .image:
            self = .image(
                path: try container.decode(String.self, forKey: .path),
                alt: try container.decodeIfPresent(String.self, forKey: .alt),
                sizeHint: try container.decodeIfPresent(ImageSizeHint.self, forKey: .sizeHint)
            )
        case .unsupported:
            self = .unsupported(try container.decode(UnsupportedBlock.self, forKey: .unsupported))
        case .footnotes:
            self = .footnotes(items: try container.decode([FootnoteItem].self, forKey: .footnotes))
        case .divider:
            self = .divider
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let level, let text, let anchor):
            try container.encode(Kind.heading, forKey: .kind)
            try container.encode(level, forKey: .level)
            try container.encode(text, forKey: .text)
            try container.encode(anchor, forKey: .anchor)
        case .paragraph(let text):
            try container.encode(Kind.paragraph, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .list(let items):
            try container.encode(Kind.list, forKey: .kind)
            try container.encode(items, forKey: .items)
        case .quote(let text):
            try container.encode(Kind.quote, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .callout(let kind, let title, let body):
            try container.encode(Kind.callout, forKey: .kind)
            try container.encode(kind, forKey: .calloutKind)
            try container.encode(title, forKey: .title)
            try container.encode(body, forKey: .body)
        case .table(let headers, let rows):
            try container.encode(Kind.table, forKey: .kind)
            try container.encode(headers, forKey: .headers)
            try container.encode(rows, forKey: .rows)
        case .code(let language, let code):
            try container.encode(Kind.code, forKey: .kind)
            try container.encodeIfPresent(language, forKey: .language)
            try container.encode(code, forKey: .code)
        case .image(let path, let alt, let sizeHint):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(alt, forKey: .alt)
            try container.encodeIfPresent(sizeHint, forKey: .sizeHint)
        case .unsupported(let unsupported):
            try container.encode(Kind.unsupported, forKey: .kind)
            try container.encode(unsupported, forKey: .unsupported)
        case .footnotes(let items):
            try container.encode(Kind.footnotes, forKey: .kind)
            try container.encode(items, forKey: .footnotes)
        case .divider:
            try container.encode(Kind.divider, forKey: .kind)
        }
    }
}
