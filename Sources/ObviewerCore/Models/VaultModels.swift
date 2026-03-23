import Foundation

public struct VaultSnapshot: Sendable {
    public let rootURL: URL
    public let notes: [VaultNote]
    public let attachments: [VaultAttachment]
    public let noteGraph: NoteGraph

    private let notesByID: [String: VaultNote]
    private let noteLookup: [String: [String]]
    private let attachmentLookup: [String: [VaultAttachment]]

    public init(rootURL: URL, notes: [VaultNote], attachments: [VaultAttachment]) {
        let sortedNotes = notes.sorted {
            if $0.modifiedAt != $1.modifiedAt {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
        let sortedAttachments = attachments.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
        let notesByID = Dictionary(uniqueKeysWithValues: sortedNotes.map { ($0.id, $0) })

        var noteLookup = [String: [String]]()
        for note in sortedNotes.sorted(by: {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }) {
            for key in note.lookupKeys {
                noteLookup[key, default: []].append(note.id)
            }
        }

        var attachmentLookup = [String: [VaultAttachment]]()
        for attachment in sortedAttachments {
            for key in attachmentLookupKeys(relativePath: attachment.relativePath) {
                attachmentLookup[key, default: []].append(attachment)
            }
        }

        self.rootURL = rootURL
        self.notes = sortedNotes
        self.attachments = sortedAttachments
        self.noteGraph = NoteGraph(notes: sortedNotes, notesByID: notesByID, noteLookup: noteLookup)
        self.notesByID = notesByID
        self.noteLookup = noteLookup
        self.attachmentLookup = attachmentLookup
    }

    public func note(withID id: String) -> VaultNote? {
        notesByID[id]
    }

    public func resolveNoteID(for target: String, from sourceNoteID: String? = nil) -> String? {
        resolveResolvedNoteID(
            for: target,
            from: sourceNoteID,
            notesByID: notesByID,
            noteLookup: noteLookup
        )
    }

    public func attachment(for path: String, from sourceNoteID: String? = nil) -> VaultAttachment? {
        let sourceRelativePath = sourceNoteID.flatMap { notesByID[$0]?.relativePath }
        for targetKey in referenceLookupKeys(for: path, sourceRelativePath: sourceRelativePath) {
            guard let candidates = attachmentLookup[targetKey], candidates.isEmpty == false else {
                continue
            }

            if candidates.count == 1 {
                return candidates[0]
            }

            return resolveBestCandidate(
                from: candidates,
                targetKey: targetKey,
                sourceRelativePath: sourceRelativePath
            ) { attachment in
                attachment.relativePath
            }
        }

        return nil
    }

    public func searchNotes(matching rawQuery: String) -> [VaultNote] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return notes
        }

        let normalizedQuery = query.lowercased()
        return notes.filter { note in
            note.searchCorpus.contains(normalizedQuery)
        }
    }
}

public struct NoteGraph: Sendable {
    public let nodes: [NoteGraphNode]
    public let edges: [NoteGraphEdge]

    private let nodesByID: [String: NoteGraphNode]
    private let outgoing: [String: [String]]
    private let incoming: [String: [String]]

    init(notes: [VaultNote], notesByID: [String: VaultNote], noteLookup: [String: [String]]) {
        var outgoing = [String: Set<String>]()
        var incoming = [String: Set<String>]()
        var edgeSet = Set<NoteGraphEdge>()

        for note in notes {
            for target in note.outboundLinks {
                guard let resolvedTarget = resolveResolvedNoteID(
                    for: target,
                    from: note.id,
                    notesByID: notesByID,
                    noteLookup: noteLookup
                ) else {
                    continue
                }

                guard resolvedTarget != note.id else {
                    continue
                }

                let edge = NoteGraphEdge(sourceID: note.id, targetID: resolvedTarget)
                guard edgeSet.insert(edge).inserted else {
                    continue
                }

                outgoing[note.id, default: []].insert(resolvedTarget)
                incoming[resolvedTarget, default: []].insert(note.id)
            }
        }

        let nodes = notes.map { note in
            NoteGraphNode(
                id: note.id,
                title: note.title,
                relativePath: note.relativePath,
                folderPath: note.folderPath,
                inboundCount: incoming[note.id]?.count ?? 0,
                outboundCount: outgoing[note.id]?.count ?? 0,
                tagCount: note.tags.count,
                wordCount: note.wordCount
            )
        }.sorted {
            if ($0.inboundCount + $0.outboundCount) != ($1.inboundCount + $1.outboundCount) {
                return ($0.inboundCount + $0.outboundCount) > ($1.inboundCount + $1.outboundCount)
            }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }

        let sortedEdges = edgeSet.sorted { lhs, rhs in
            if lhs.sourceID != rhs.sourceID {
                return lhs.sourceID.localizedCaseInsensitiveCompare(rhs.sourceID) == .orderedAscending
            }
            return lhs.targetID.localizedCaseInsensitiveCompare(rhs.targetID) == .orderedAscending
        }

        self.nodes = nodes
        self.edges = sortedEdges
        self.nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        self.outgoing = outgoing.mapValues { noteIDs in
            noteIDs.sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }
        self.incoming = incoming.mapValues { noteIDs in
            noteIDs.sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }
    }

    public func node(withID id: String) -> NoteGraphNode? {
        nodesByID[id]
    }

    public func outboundNoteIDs(from noteID: String) -> [String] {
        outgoing[noteID] ?? []
    }

    public func inboundNoteIDs(to noteID: String) -> [String] {
        incoming[noteID] ?? []
    }

    public func adjacentNoteIDs(for noteID: String) -> [String] {
        Array(Set(outboundNoteIDs(from: noteID) + inboundNoteIDs(to: noteID))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public func localSubgraph(
        around centerID: String,
        highlightedIDs: Set<String> = []
    ) -> NoteGraphSubgraph {
        guard nodesByID[centerID] != nil else {
            return NoteGraphSubgraph(nodes: [], edges: [], highlightedNodeIDs: highlightedIDs, centerNodeID: nil)
        }

        var visibleIDs = Set([centerID])
        visibleIDs.formUnion(outboundNoteIDs(from: centerID))
        visibleIDs.formUnion(inboundNoteIDs(to: centerID))

        if visibleIDs.count < 14 {
            let firstRing = Array(visibleIDs)
            for noteID in firstRing {
                for neighbor in adjacentNoteIDs(for: noteID) {
                    visibleIDs.insert(neighbor)
                    if visibleIDs.count >= 18 {
                        break
                    }
                }
                if visibleIDs.count >= 18 {
                    break
                }
            }
        }

        return subgraph(
            visibleNoteIDs: visibleIDs,
            highlightedIDs: highlightedIDs.union([centerID]),
            centerNodeID: centerID
        )
    }

    public func globalSubgraph(
        visibleNoteIDs: Set<String>,
        highlightedIDs: Set<String> = [],
        centerNodeID: String? = nil
    ) -> NoteGraphSubgraph {
        let effectiveVisibleNoteIDs = visibleNoteIDs.isEmpty
            ? Set(nodesByID.keys)
            : visibleNoteIDs

        return subgraph(
            visibleNoteIDs: effectiveVisibleNoteIDs,
            highlightedIDs: highlightedIDs,
            centerNodeID: centerNodeID
        )
    }

    private func subgraph(
        visibleNoteIDs: Set<String>,
        highlightedIDs: Set<String>,
        centerNodeID: String?
    ) -> NoteGraphSubgraph {
        let nodes = visibleNoteIDs.compactMap { nodesByID[$0] }.sorted {
            if $0.id == centerNodeID { return true }
            if $1.id == centerNodeID { return false }
            if ($0.inboundCount + $0.outboundCount) != ($1.inboundCount + $1.outboundCount) {
                return ($0.inboundCount + $0.outboundCount) > ($1.inboundCount + $1.outboundCount)
            }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }

        let edges = edges.filter {
            visibleNoteIDs.contains($0.sourceID) && visibleNoteIDs.contains($0.targetID)
        }

        return NoteGraphSubgraph(
            nodes: nodes,
            edges: edges,
            highlightedNodeIDs: highlightedIDs,
            centerNodeID: centerNodeID
        )
    }
}

public struct NoteGraphNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let relativePath: String
    public let folderPath: String
    public let inboundCount: Int
    public let outboundCount: Int
    public let tagCount: Int
    public let wordCount: Int
}

public struct NoteGraphEdge: Hashable, Sendable {
    public let sourceID: String
    public let targetID: String

    public init(sourceID: String, targetID: String) {
        self.sourceID = sourceID
        self.targetID = targetID
    }
}

public struct NoteGraphSubgraph: Sendable {
    public let nodes: [NoteGraphNode]
    public let edges: [NoteGraphEdge]
    public let highlightedNodeIDs: Set<String>
    public let centerNodeID: String?

    public init(
        nodes: [NoteGraphNode],
        edges: [NoteGraphEdge],
        highlightedNodeIDs: Set<String>,
        centerNodeID: String?
    ) {
        self.nodes = nodes
        self.edges = edges
        self.highlightedNodeIDs = highlightedNodeIDs
        self.centerNodeID = centerNodeID
    }
}

public struct NoteFrontmatter: Hashable, Sendable {
    public let entries: [FrontmatterEntry]

    public init(entries: [FrontmatterEntry] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    public func value(for key: String) -> FrontmatterValue? {
        let normalizedKey = normalizeFrontmatterKey(key)
        return entries.first { entry in
            normalizeFrontmatterKey(entry.key) == normalizedKey
        }?.value
    }

    public var aliases: [String] {
        value(for: "aliases")?.stringValues.filter { $0.isEmpty == false } ?? []
    }

    public var tags: [String] {
        normalizedTags(from: value(for: "tags"))
    }

    public var searchableValues: [String] {
        entries.flatMap { entry in
            [entry.key] + entry.value.searchableTextComponents
        }
    }

    public func displayEntries(limit: Int? = nil) -> [FrontmatterEntry] {
        let prioritizedKeys = ["status", "aliases", "project", "owner", "created", "updated", "date", "category"]
        let excludedKeys = Set(["title", "tags"])

        let prioritized = entries.filter { entry in
            let normalizedKey = normalizeFrontmatterKey(entry.key)
            return excludedKeys.contains(normalizedKey) == false
                && prioritizedKeys.contains(normalizedKey)
        }.sorted { lhs, rhs in
            let lhsIndex = prioritizedKeys.firstIndex(of: normalizeFrontmatterKey(lhs.key)) ?? prioritizedKeys.count
            let rhsIndex = prioritizedKeys.firstIndex(of: normalizeFrontmatterKey(rhs.key)) ?? prioritizedKeys.count
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }

        let remaining = entries.filter { entry in
            let normalizedKey = normalizeFrontmatterKey(entry.key)
            return excludedKeys.contains(normalizedKey) == false
                && prioritizedKeys.contains(normalizedKey) == false
        }

        let combined = prioritized + remaining
        if let limit {
            return Array(combined.prefix(limit))
        }
        return combined
    }
}

public struct FrontmatterEntry: Hashable, Sendable {
    public let key: String
    public let value: FrontmatterValue

    public init(key: String, value: FrontmatterValue) {
        self.key = key
        self.value = value
    }
}

public enum FrontmatterValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([FrontmatterValue])

    public var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return formatFrontmatterNumber(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array:
            return nil
        }
    }

    public var stringValues: [String] {
        switch self {
        case .string(let value):
            return [value]
        case .number(let value):
            return [formatFrontmatterNumber(value)]
        case .bool(let value):
            return [value ? "true" : "false"]
        case .array(let values):
            return values.flatMap(\.stringValues)
        }
    }

    public var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return formatFrontmatterNumber(value)
        case .bool(let value):
            return value ? "True" : "False"
        case .array(let values):
            return values.map(\.displayText).joined(separator: ", ")
        }
    }

    fileprivate var searchableTextComponents: [String] {
        switch self {
        case .string(let value):
            return [value]
        case .number(let value):
            return [formatFrontmatterNumber(value)]
        case .bool(let value):
            return [value ? "true" : "false"]
        case .array(let values):
            return values.flatMap(\.searchableTextComponents)
        }
    }
}

public struct VaultNote: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let relativePath: String
    public let folderPath: String
    public let previewText: String
    public let frontmatter: NoteFrontmatter
    public let tags: [String]
    public let outboundLinks: [String]
    public let tableOfContents: [TableOfContentsItem]
    public let blocks: [RenderBlock]
    public let wordCount: Int
    public let readingTimeMinutes: Int
    public let modifiedAt: Date
    public let searchCorpus: String

    public init(
        id: String,
        title: String,
        relativePath: String,
        folderPath: String,
        previewText: String,
        frontmatter: NoteFrontmatter = NoteFrontmatter(),
        tags: [String],
        outboundLinks: [String],
        tableOfContents: [TableOfContentsItem],
        blocks: [RenderBlock],
        wordCount: Int,
        readingTimeMinutes: Int,
        modifiedAt: Date,
        searchCorpus: String? = nil
    ) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.folderPath = folderPath
        self.previewText = previewText
        self.frontmatter = frontmatter
        self.tags = tags
        self.outboundLinks = outboundLinks
        self.tableOfContents = tableOfContents
        self.blocks = blocks
        self.wordCount = wordCount
        self.readingTimeMinutes = readingTimeMinutes
        self.modifiedAt = modifiedAt
        self.searchCorpus = searchCorpus ?? makeSearchCorpus(
            title: title,
            relativePath: relativePath,
            previewText: previewText,
            frontmatter: frontmatter,
            tags: tags
        )
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
            ] + frontmatter.aliases.map(normalizeVaultReference))
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
    public let modifiedAt: Date

    public init(relativePath: String, url: URL, kind: Kind, modifiedAt: Date = .distantPast) {
        self.relativePath = relativePath
        self.url = url
        self.kind = kind
        self.modifiedAt = modifiedAt
    }
}

public enum RenderBlock: Hashable, Sendable {
    case heading(level: Int, text: RichText, anchor: String)
    case paragraph(text: RichText)
    case list(items: [RenderListItem])
    case quote(text: RichText)
    case callout(kind: CalloutKind, title: RichText, body: RichText)
    case table(headers: [RichText], rows: [[RichText]])
    case code(language: String?, code: String)
    case image(path: String, alt: String?, sizeHint: ImageSizeHint?)
    case unsupported(UnsupportedBlock)
    case footnotes(items: [FootnoteItem])
    case divider
}

public struct UnsupportedBlock: Hashable, Sendable {
    public let title: String
    public let body: String
    public let attachmentPath: String?

    public init(title: String, body: String, attachmentPath: String? = nil) {
        self.title = title
        self.body = body
        self.attachmentPath = attachmentPath
    }
}

public struct FootnoteItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let text: RichText

    public init(id: String, label: String, text: RichText) {
        self.id = id
        self.label = label
        self.text = text
    }
}

public struct RenderListItem: Hashable, Sendable {
    public let marker: RenderListMarker
    public let text: RichText
    public let children: [RenderListItem]

    public init(marker: RenderListMarker, text: RichText, children: [RenderListItem] = []) {
        self.marker = marker
        self.text = text
        self.children = children
    }
}

public enum RenderListMarker: Hashable, Sendable {
    case unordered
    case ordered(Int)
    case task(isCompleted: Bool)
}

public struct ImageSizeHint: Hashable, Sendable {
    public let width: Double?
    public let height: Double?

    public init(width: Double?, height: Double?) {
        self.width = width
        self.height = height
    }

    public var hasExplicitDimensions: Bool {
        width != nil || height != nil
    }
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
    case image(path: String, alt: String?, sizeHint: ImageSizeHint?)
    case tag(String)

    public var plainText: String {
        switch self {
        case .text(let value), .strong(let value), .emphasis(let value), .code(let value):
            return value
        case .link(let label, _):
            return label
        case .image(let path, let alt, _):
            let trimmedAlt = alt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedAlt.isEmpty == false {
                return trimmedAlt
            }
            let basename = (path as NSString).lastPathComponent
            return basename.isEmpty ? path : basename
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

public func normalizeFrontmatterKey(_ key: String) -> String {
    key
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
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

private func resolveResolvedNoteID(
    for target: String,
    from sourceNoteID: String?,
    notesByID: [String: VaultNote],
    noteLookup: [String: [String]]
) -> String? {
    let sourceRelativePath = sourceNoteID.flatMap { notesByID[$0]?.relativePath }
    for targetKey in referenceLookupKeys(for: target, sourceRelativePath: sourceRelativePath) {
        guard let candidates = noteLookup[targetKey], candidates.isEmpty == false else {
            continue
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        return resolveBestCandidate(
            from: candidates,
            targetKey: targetKey,
            sourceRelativePath: sourceRelativePath
        ) { candidateID in
            notesByID[candidateID]?.relativePath ?? candidateID
        }
    }

    return nil
}

private func resolveBestCandidate<Candidate>(
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

private func folderPath(for relativePath: String) -> String {
    let folder = (relativePath as NSString).deletingLastPathComponent
    guard folder != "." else { return "" }
    return normalizeVaultReference(folder)
}

private func normalizedTags(from value: FrontmatterValue?) -> [String] {
    guard let value else {
        return []
    }

    var seen = Set<String>()
    var ordered = [String]()

    for rawValue in value.stringValues {
        let parts = rawValue.contains(",")
            ? rawValue.split(separator: ",").map(String.init)
            : [rawValue]

        for part in parts {
            let normalized = part
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^#+"#, with: "", options: .regularExpression)

            guard normalized.isEmpty == false else {
                continue
            }

            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }
    }

    return ordered
}

private func formatFrontmatterNumber(_ value: Double) -> String {
    if value.rounded(.towardZero) == value {
        return String(Int(value))
    }
    return value.formatted(.number.precision(.fractionLength(0 ... 3)))
}

private func makeSearchCorpus(
    title: String,
    relativePath: String,
    previewText: String,
    frontmatter: NoteFrontmatter,
    tags: [String]
) -> String {
    let tagComponents = tags.flatMap { tag in
        [tag, "#\(tag)"]
    }

    return ([title, relativePath, previewText] + frontmatter.searchableValues + tagComponents)
        .map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        .filter { $0.isEmpty == false }
        .joined(separator: "\n")
}

private func referenceLookupKeys(for target: String, sourceRelativePath: String?) -> [String] {
    let normalizedTarget = normalizeVaultReference(target)
    guard let sourceRelativePath,
          let relativeTarget = resolveRelativeReference(target, from: sourceRelativePath),
          relativeTarget != normalizedTarget else {
        return [normalizedTarget]
    }

    return [normalizedTarget, relativeTarget]
}

private func resolveRelativeReference(_ target: String, from sourceRelativePath: String) -> String? {
    let trimmed = target
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")

    guard trimmed.isEmpty == false, trimmed.hasPrefix("/") == false else {
        return nil
    }

    guard trimmed.hasPrefix(".") || trimmed.contains("/") else {
        return nil
    }

    let sourceFolderComponents = folderPath(for: sourceRelativePath)
        .split(separator: "/")
        .map(String.init)
    let targetComponents = trimmed
        .split(separator: "/", omittingEmptySubsequences: false)
        .map(String.init)

    var resolvedComponents = sourceFolderComponents
    for component in targetComponents {
        switch component {
        case "", ".":
            continue
        case "..":
            guard resolvedComponents.isEmpty == false else {
                return nil
            }
            resolvedComponents.removeLast()
        default:
            resolvedComponents.append(component)
        }
    }

    return normalizeVaultReference(resolvedComponents.joined(separator: "/"))
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
