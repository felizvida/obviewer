import Foundation
import ObviewerCore

/// Assembles everything the reader page needs for one note: its source,
/// header metadata, backlinks, which wiki links resolve, and the tree of
/// `![[embeds]]` (resolved here so the page never touches the file system).
public struct ReaderPayloadBuilder: Sendable {
    public static let maximumEmbedDepth = 4
    public static let embedBudgetBytes = 6 * 1024 * 1024
    public static let maximumEmbedsPerNote = 64

    public let snapshot: VaultSnapshot
    public let flavor: ReaderFlavor
    public let dokuwiki: ReaderDokuWikiInfo?
    private let loadSource: @Sendable (URL) throws -> String

    public init(
        snapshot: VaultSnapshot,
        flavor: ReaderFlavor,
        dokuwiki: ReaderDokuWikiInfo? = nil,
        loadSource: @escaping @Sendable (URL) throws -> String = { try NoteSourceLoader.load($0) }
    ) {
        self.snapshot = snapshot
        self.flavor = flavor
        self.dokuwiki = dokuwiki
        self.loadSource = loadSource
    }

    public func fileURL(for note: VaultNote) -> URL {
        snapshot.rootURL.appendingPathComponent(note.relativePath)
    }

    /// Loads the note's source from disk and builds the payload.
    public func build(for note: VaultNote, options: ReaderRenderOptions = ReaderRenderOptions()) throws -> ReaderRenderPayload {
        let source = try loadSource(fileURL(for: note))
        return build(for: note, source: source, options: options)
    }

    public func build(for note: VaultNote, source: String, options: ReaderRenderOptions = ReaderRenderOptions()) -> ReaderRenderPayload {
        var budget = Self.embedBudgetBytes
        let embeds = flavor == .dokuwiki
            ? [:]
            : resolveEmbeds(in: source, hostNoteID: note.id, ancestors: [note.id], depth: 1, budget: &budget)

        return ReaderRenderPayload(
            noteID: note.id,
            relativePath: note.relativePath,
            title: note.title,
            flavor: flavor,
            source: source,
            header: options.showHeader ? header(for: note) : nil,
            embeds: embeds,
            resolvedLinks: resolvedLinks(in: source, from: note.id),
            backlinks: options.showBacklinks ? backlinks(for: note) : [],
            dokuwiki: flavor == .dokuwiki ? dokuwiki : nil,
            options: options
        )
    }

    // MARK: - Header and backlinks

    public func header(for note: VaultNote) -> ReaderHeader {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let modified = note.modifiedAt == .distantPast ? nil : formatter.string(from: note.modifiedAt)
        return ReaderHeader(
            path: note.relativePath,
            tags: note.tags,
            properties: note.frontmatter.displayEntries().map {
                ReaderProperty(key: $0.key, value: $0.value.displayText)
            },
            readingTime: note.readingTimeMinutes > 0 ? note.readingTimeMinutes : nil,
            modified: modified
        )
    }

    public func backlinks(for note: VaultNote) -> [ReaderBacklink] {
        snapshot.noteGraph.inboundNoteIDs(to: note.id)
            .compactMap { snapshot.note(withID: $0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { ReaderBacklink(noteID: $0.id, title: $0.title, path: $0.folderPath.isEmpty ? nil : $0.folderPath) }
    }

    // MARK: - Links

    public func resolvedLinks(in source: String, from noteID: String) -> [String: Bool] {
        var result = [String: Bool]()
        if flavor == .dokuwiki {
            for id in DokuWikiSyntax.linkIDs(in: source, fromNoteID: noteID, pagesBase: dokuwiki?.pagesBase ?? "") {
                result[id] = DokuWikiSyntax.noteID(forPageID: id, in: snapshot, pagesBase: dokuwiki?.pagesBase ?? "") != nil
            }
            return result
        }
        for inner in WikiSyntax.wikiLinkContents(in: source) {
            let target = WikiSyntax.parseTarget(inner)
            guard target.note.isEmpty == false, result[target.note] == nil else { continue }
            result[target.note] = snapshot.resolveNoteID(for: target.note, from: noteID) != nil
                || snapshot.attachment(for: target.note, from: noteID) != nil
        }
        return result
    }

    // MARK: - Embeds

    private func resolveEmbeds(
        in source: String,
        hostNoteID: String,
        ancestors: Set<String>,
        depth: Int,
        budget: inout Int
    ) -> [String: ReaderEmbed] {
        var embeds = [String: ReaderEmbed]()
        for inner in WikiSyntax.embedContents(in: source).prefix(Self.maximumEmbedsPerNote) {
            let target = WikiSyntax.parseTarget(inner)
            guard embeds[target.raw] == nil else { continue }

            let kind = WikiSyntax.embedKind(forPath: target.note)
            if kind != .note {
                if let attachment = snapshot.attachment(for: target.note, from: hostNoteID) {
                    embeds[target.raw] = ReaderEmbed(
                        status: .ok,
                        kind: ReaderEmbed.Kind(rawValue: kind.rawValue) ?? .file,
                        path: attachment.relativePath,
                        name: (attachment.relativePath as NSString).lastPathComponent
                    )
                }
                // Unknown attachments are left out so the page can try a path relative to the note.
                continue
            }

            let noteID: String?
            if target.note.isEmpty {
                noteID = hostNoteID
            } else {
                noteID = snapshot.resolveNoteID(for: target.note, from: hostNoteID)
            }
            guard let noteID, let note = snapshot.note(withID: noteID) else {
                embeds[target.raw] = .problem(.missing)
                continue
            }
            if ancestors.contains(noteID) && (target.anchor == nil || noteID != hostNoteID) {
                embeds[target.raw] = .problem(.cycle)
                continue
            }
            if depth > Self.maximumEmbedDepth {
                embeds[target.raw] = .problem(.depth)
                continue
            }

            let markdown: String
            do {
                markdown = try loadSource(fileURL(for: note))
            } catch {
                embeds[target.raw] = .problem(.unreadable)
                continue
            }
            let cost = markdown.utf8.count
            guard cost <= budget else {
                embeds[target.raw] = .problem(.tooLarge)
                continue
            }
            budget -= cost

            let nested = noteID == hostNoteID
                ? [:]
                : resolveEmbeds(in: markdown, hostNoteID: noteID, ancestors: ancestors.union([noteID]), depth: depth + 1, budget: &budget)
            embeds[target.raw] = ReaderEmbed(
                status: .ok,
                kind: .note,
                noteID: note.id,
                relativePath: note.relativePath,
                title: note.title,
                markdown: markdown,
                embeds: nested
            )
        }
        return embeds
    }
}
