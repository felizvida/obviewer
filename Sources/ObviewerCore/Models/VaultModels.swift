import Foundation

public struct VaultSnapshot: Sendable {
    public let rootURL: URL
    public let notes: [VaultNote]
    public let attachments: [VaultAttachment]

    private let notesByID: [String: VaultNote]
    private let noteLookup: [String: [String]]
    private let attachmentLookup: [String: [VaultAttachment]]

    public init(rootURL: URL, notes: [VaultNote], attachments: [VaultAttachment]) {
        self.rootURL = rootURL
        self.notes = notes.sorted {
            if $0.modifiedAt != $1.modifiedAt {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
        self.attachments = attachments.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
        self.notesByID = Dictionary(uniqueKeysWithValues: self.notes.map { ($0.id, $0) })

        var noteLookup = [String: [String]]()
        for note in self.notes.sorted(by: {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }) {
            for key in note.lookupKeys {
                noteLookup[key, default: []].append(note.id)
            }
        }
        self.noteLookup = noteLookup

        var attachmentLookup = [String: [VaultAttachment]]()
        for attachment in self.attachments {
            for key in attachmentLookupKeys(relativePath: attachment.relativePath) {
                attachmentLookup[key, default: []].append(attachment)
            }
        }
        self.attachmentLookup = attachmentLookup
    }

    public func note(withID id: String) -> VaultNote? {
        notesByID[id]
    }

    public func resolveNoteID(for target: String, from sourceNoteID: String? = nil) -> String? {
        let normalizedTarget = normalizeVaultReference(target)
        guard let candidates = noteLookup[normalizedTarget], candidates.isEmpty == false else {
            return nil
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        let sourceRelativePath = sourceNoteID.flatMap { notesByID[$0]?.relativePath }
        return bestCandidate(
            from: candidates,
            targetKey: normalizedTarget,
            sourceRelativePath: sourceRelativePath
        ) { candidateID in
            notesByID[candidateID]?.relativePath ?? candidateID
        }
    }

    public func attachment(for path: String, from sourceNoteID: String? = nil) -> VaultAttachment? {
        let normalizedTarget = normalizeVaultReference(path)
        guard let candidates = attachmentLookup[normalizedTarget], candidates.isEmpty == false else {
            return nil
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        let sourceRelativePath = sourceNoteID.flatMap { notesByID[$0]?.relativePath }
        return bestCandidate(
            from: candidates,
            targetKey: normalizedTarget,
            sourceRelativePath: sourceRelativePath
        ) { attachment in
            attachment.relativePath
        }
    }

    private func bestCandidate<Candidate>(
        from candidates: [Candidate],
        targetKey: String,
        sourceRelativePath: String?,
        relativePath: (Candidate) -> String
    ) -> Candidate? {
        let sourceFolder = sourceRelativePath.map(folderPath(for:))

        return candidates.sorted { lhs, rhs in
            let lhsPath = relativePath(lhs)
            let rhsPath = relativePath(rhs)
            let lhsScore = resolutionScore(
                for: lhsPath,
                targetKey: targetKey,
                sourceFolder: sourceFolder
            )
            let rhsScore = resolutionScore(
                for: rhsPath,
                targetKey: targetKey,
                sourceFolder: sourceFolder
            )

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            return lhsPath.localizedCaseInsensitiveCompare(rhsPath) == .orderedAscending
        }.first
    }

    private func resolutionScore(
        for candidateRelativePath: String,
        targetKey: String,
        sourceFolder: String?
    ) -> (Int, Int, Int, Int) {
        let normalizedCandidatePath = normalizeVaultReference(candidateRelativePath)
        let normalizedStem = normalizeVaultReference((candidateRelativePath as NSString).deletingPathExtension)
        let candidateFolder = folderPath(for: candidateRelativePath)
        let exactPathMatch = (normalizedCandidatePath == targetKey || normalizedStem == targetKey) ? 1 : 0

        guard let sourceFolder else {
            return (exactPathMatch, 0, 0, 0)
        }

        return (
            exactPathMatch,
            candidateFolder == sourceFolder ? 1 : 0,
            sharedPathPrefixLength(lhs: sourceFolder, rhs: candidateFolder),
            -pathDistance(from: sourceFolder, to: candidateFolder)
        )
    }
}

public struct VaultNote: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let relativePath: String
    public let folderPath: String
    public let previewText: String
    public let tags: [String]
    public let outboundLinks: [String]
    public let tableOfContents: [TableOfContentsItem]
    public let blocks: [RenderBlock]
    public let wordCount: Int
    public let readingTimeMinutes: Int
    public let modifiedAt: Date

    public init(
        id: String,
        title: String,
        relativePath: String,
        folderPath: String,
        previewText: String,
        tags: [String],
        outboundLinks: [String],
        tableOfContents: [TableOfContentsItem],
        blocks: [RenderBlock],
        wordCount: Int,
        readingTimeMinutes: Int,
        modifiedAt: Date
    ) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.folderPath = folderPath
        self.previewText = previewText
        self.tags = tags
        self.outboundLinks = outboundLinks
        self.tableOfContents = tableOfContents
        self.blocks = blocks
        self.wordCount = wordCount
        self.readingTimeMinutes = readingTimeMinutes
        self.modifiedAt = modifiedAt
    }

    fileprivate var lookupKeys: [String] {
        let pathWithoutExtension = (relativePath as NSString).deletingPathExtension
        let lastPathComponent = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        return Array(
            Set([
                normalizeVaultReference(relativePath),
                normalizeVaultReference(pathWithoutExtension),
                normalizeVaultReference(lastPathComponent),
                normalizeVaultReference(title),
            ])
        )
    }
}

public struct VaultAttachment: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case image
        case pdf
        case audio
        case video
        case other
    }

    public let relativePath: String
    public let url: URL
    public let kind: Kind

    public init(relativePath: String, url: URL, kind: Kind) {
        self.relativePath = relativePath
        self.url = url
        self.kind = kind
    }
}

public enum RenderBlock: Hashable, Sendable {
    case heading(level: Int, text: RichText, anchor: String)
    case paragraph(text: RichText)
    case bulletList(items: [RichText])
    case quote(text: RichText)
    case callout(kind: CalloutKind, title: RichText, body: RichText)
    case table(headers: [RichText], rows: [[RichText]])
    case code(language: String?, code: String)
    case image(path: String, alt: String?)
    case divider
}

public struct TableOfContentsItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let level: Int
    public let title: String

    public init(id: String, level: Int, title: String) {
        self.id = id
        self.level = level
        self.title = title
    }
}

public struct RichText: Hashable, Sendable {
    public let runs: [InlineRun]

    public init(runs: [InlineRun]) {
        self.runs = runs
    }

    public static func plain(_ value: String) -> RichText {
        RichText(runs: [.text(value)])
    }

    public var plainText: String {
        runs.map(\.plainText).joined()
    }

    public var isEmpty: Bool {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum InlineRun: Hashable, Sendable {
    case text(String)
    case strong(String)
    case emphasis(String)
    case code(String)
    case link(label: String, destination: LinkDestination)
    case tag(String)

    public var plainText: String {
        switch self {
        case .text(let value), .strong(let value), .emphasis(let value), .code(let value):
            return value
        case .link(let label, _):
            return label
        case .tag(let value):
            return "#\(value)"
        }
    }
}

public enum LinkDestination: Hashable, Sendable {
    case note(target: String, anchor: String?)
    case anchor(String)
    case attachment(String)
    case external(String)
}

public enum CalloutKind: String, Hashable, Sendable {
    case note
    case info
    case tip
    case warning
    case danger
    case success

    public var label: String {
        rawValue.capitalized
    }
}

public func normalizeVaultReference(_ reference: String) -> String {
    var trimmed = reference
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
        .replacingOccurrences(of: #"^\./"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    if trimmed.lowercased().hasSuffix(".md") {
        trimmed.removeLast(3)
    }

    return trimmed.lowercased()
}

public func makeAnchorSlug(_ value: String) -> String {
    let lowercased = value.lowercased()
    let replaced = lowercased.replacingOccurrences(
        of: #"[^a-z0-9]+"#,
        with: "-",
        options: .regularExpression
    )
    let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "section" : trimmed
}

private func attachmentLookupKeys(relativePath: String) -> [String] {
    let basename = (relativePath as NSString).lastPathComponent
    return Array(
        Set([
            normalizeVaultReference(relativePath),
            normalizeVaultReference(basename),
        ])
    )
}

private func folderPath(for relativePath: String) -> String {
    let folder = (relativePath as NSString).deletingLastPathComponent
    guard folder != "." else { return "" }
    return normalizeVaultReference(folder)
}

private func sharedPathPrefixLength(lhs: String, rhs: String) -> Int {
    let lhsComponents = lhs.split(separator: "/")
    let rhsComponents = rhs.split(separator: "/")
    let sharedCount = min(lhsComponents.count, rhsComponents.count)

    var matched = 0
    while matched < sharedCount, lhsComponents[matched] == rhsComponents[matched] {
        matched += 1
    }

    return matched
}

private func pathDistance(from lhs: String, to rhs: String) -> Int {
    let lhsComponents = lhs.split(separator: "/")
    let rhsComponents = rhs.split(separator: "/")
    let sharedLength = sharedPathPrefixLength(lhs: lhs, rhs: rhs)
    return (lhsComponents.count - sharedLength) + (rhsComponents.count - sharedLength)
}
