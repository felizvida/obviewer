import Foundation

/// Messages posted by the reader page through `webkit.messageHandlers.obviewer`.
public enum ReaderEvent: Equatable, Sendable {
    case ready
    case rendered(noteID: String, headings: [ReaderHeading])
    case diagramsRendered(noteID: String)
    case link(ReaderLinkRequest)
    case assetError(source: String)
    case copy(text: String)
    /// A JavaScript error or unhandled rejection in the page (diagnostics only).
    case jsError(String)
    /// A load blocked by the page's Content-Security-Policy (diagnostics only).
    case cspViolation(String)

    /// Parses a message body. Anything unexpected is ignored rather than trusted.
    public init?(messageBody: Any) {
        guard let body = messageBody as? [String: Any], let type = body["type"] as? String else {
            return nil
        }

        switch type {
        case "ready":
            self = .ready
        case "rendered":
            let headings = (body["headings"] as? [[String: Any]] ?? []).compactMap { raw -> ReaderHeading? in
                guard let text = raw["text"] as? String, let id = raw["id"] as? String else { return nil }
                let level = (raw["level"] as? NSNumber)?.intValue ?? 1
                return ReaderHeading(level: min(max(level, 1), 6), text: text, id: id)
            }
            self = .rendered(noteID: body["noteID"] as? String ?? "", headings: headings)
        case "diagramsRendered":
            self = .diagramsRendered(noteID: body["noteID"] as? String ?? "")
        case "link":
            guard let request = ReaderLinkRequest(body: body) else { return nil }
            self = .link(request)
        case "assetError":
            self = .assetError(source: body["src"] as? String ?? "")
        case "copy":
            guard let text = body["text"] as? String else { return nil }
            self = .copy(text: String(text.prefix(5_000_000)))
        case "jsError":
            self = .jsError(String((body["message"] as? String ?? "unknown").prefix(2_000)))
        case "cspViolation":
            self = .cspViolation(String((body["message"] as? String ?? "unknown").prefix(2_000)))
        default:
            return nil
        }
    }
}

public struct ReaderLinkRequest: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// `[[wiki link]]` or a DokuWiki page ID.
        case wiki
        /// Relative path from a Markdown link (`[x](other.md)`, `[pdf](files/a.pdf)`).
        case path
        /// A backlink entry; `target` is a note ID.
        case noteID
        /// http(s), mailto, obsidian:// and similar.
        case external
        case tag
    }

    public let kind: Kind
    public let target: String
    public let anchor: String?
    public let sourceNoteID: String?
    public let opensNewWindow: Bool

    public init(kind: Kind, target: String, anchor: String? = nil, sourceNoteID: String? = nil, opensNewWindow: Bool = false) {
        self.kind = kind
        self.target = target
        self.anchor = anchor
        self.sourceNoteID = sourceNoteID
        self.opensNewWindow = opensNewWindow
    }

    init?(body: [String: Any]) {
        guard let rawKind = body["kind"] as? String, let kind = Kind(rawValue: rawKind) else { return nil }
        let target = (kind == .external ? body["href"] : body["target"]) as? String ?? ""
        guard target.count <= 8_192 else { return nil }
        let anchor = (body["anchor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.init(
            kind: kind,
            target: target,
            anchor: anchor,
            sourceNoteID: body["from"] as? String,
            opensNewWindow: (body["newWindow"] as? Bool) ?? false
        )
    }
}
