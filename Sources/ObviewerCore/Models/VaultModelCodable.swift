import Foundation

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
