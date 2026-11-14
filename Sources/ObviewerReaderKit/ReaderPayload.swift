import Foundation

/// The JSON document handed to `window.obviewer.render(...)`.
/// Field names match `Renderer/src/core/page.js`.
public struct ReaderRenderPayload: Codable, Equatable, Sendable {
    public var noteID: String
    public var relativePath: String
    public var title: String
    public var flavor: ReaderFlavor
    public var source: String
    public var header: ReaderHeader?
    public var embeds: [String: ReaderEmbed]
    public var resolvedLinks: [String: Bool]
    public var backlinks: [ReaderBacklink]
    public var dokuwiki: ReaderDokuWikiInfo?
    public var options: ReaderRenderOptions

    public init(
        noteID: String,
        relativePath: String,
        title: String,
        flavor: ReaderFlavor,
        source: String,
        header: ReaderHeader? = nil,
        embeds: [String: ReaderEmbed] = [:],
        resolvedLinks: [String: Bool] = [:],
        backlinks: [ReaderBacklink] = [],
        dokuwiki: ReaderDokuWikiInfo? = nil,
        options: ReaderRenderOptions = ReaderRenderOptions()
    ) {
        self.noteID = noteID
        self.relativePath = relativePath
        self.title = title
        self.flavor = flavor
        self.source = source
        self.header = header
        self.embeds = embeds
        self.resolvedLinks = resolvedLinks
        self.backlinks = backlinks
        self.dokuwiki = dokuwiki
        self.options = options
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

public enum ReaderFlavor: String, Codable, Sendable {
    case markdown
    case obsidian
    case dokuwiki
}

public struct ReaderHeader: Codable, Equatable, Sendable {
    public var path: String?
    public var tags: [String]
    public var properties: [ReaderProperty]
    public var readingTime: Int?
    public var modified: String?

    public init(path: String?, tags: [String], properties: [ReaderProperty], readingTime: Int?, modified: String?) {
        self.path = path
        self.tags = tags
        self.properties = properties
        self.readingTime = readingTime
        self.modified = modified
    }
}

public struct ReaderProperty: Codable, Equatable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct ReaderBacklink: Codable, Equatable, Sendable {
    public var noteID: String
    public var title: String
    public var path: String?

    public init(noteID: String, title: String, path: String?) {
        self.noteID = noteID
        self.title = title
        self.path = path
    }
}

public struct ReaderDokuWikiInfo: Codable, Equatable, Sendable {
    public var pagesBase: String
    public var mediaBase: String

    public init(pagesBase: String, mediaBase: String) {
        self.pagesBase = pagesBase
        self.mediaBase = mediaBase
    }
}

public struct ReaderRenderOptions: Codable, Equatable, Sendable {
    public var showHeader: Bool
    public var showBacklinks: Bool
    public var preserveScroll: Bool
    public var anchor: String?
    /// Static HTML for Quick Look: raw HTML shown as text, MathML math, no images or diagrams.
    public var staticMode: Bool

    public init(
        showHeader: Bool = true,
        showBacklinks: Bool = true,
        preserveScroll: Bool = true,
        anchor: String? = nil,
        staticMode: Bool = false
    ) {
        self.showHeader = showHeader
        self.showBacklinks = showBacklinks
        self.preserveScroll = preserveScroll
        self.anchor = anchor
        self.staticMode = staticMode
    }
}

/// A pre-resolved `![[embed]]`. Note embeds carry the embedded note's source
/// and their own nested embeds, so the tree itself encodes depth and cycles.
public struct ReaderEmbed: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case ok
        case missing
        case cycle
        case depth
        case unreadable
        case tooLarge
    }

    public enum Kind: String, Codable, Sendable {
        case note
        case image
        case pdf
        case audio
        case video
        case file
    }

    public var status: Status
    public var kind: Kind?
    public var noteID: String?
    public var relativePath: String?
    public var title: String?
    public var markdown: String?
    public var path: String?
    public var name: String?
    public var embeds: [String: ReaderEmbed]?

    public init(
        status: Status,
        kind: Kind? = nil,
        noteID: String? = nil,
        relativePath: String? = nil,
        title: String? = nil,
        markdown: String? = nil,
        path: String? = nil,
        name: String? = nil,
        embeds: [String: ReaderEmbed]? = nil
    ) {
        self.status = status
        self.kind = kind
        self.noteID = noteID
        self.relativePath = relativePath
        self.title = title
        self.markdown = markdown
        self.path = path
        self.name = name
        self.embeds = embeds
    }

    public static func problem(_ status: Status) -> ReaderEmbed {
        ReaderEmbed(status: status)
    }
}

public struct ReaderHeading: Equatable, Sendable, Identifiable, Hashable {
    public let level: Int
    public let text: String
    public let id: String

    public init(level: Int, text: String, id: String) {
        self.level = level
        self.text = text
        self.id = id
    }
}
