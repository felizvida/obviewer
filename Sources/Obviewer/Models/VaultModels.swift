import Foundation

struct VaultSnapshot: Sendable {
    let rootURL: URL
    let notes: [VaultNote]
    let attachments: [String: VaultAttachment]

    private let noteLookup: [String: String]

    init(rootURL: URL, notes: [VaultNote], attachments: [String: VaultAttachment]) {
        self.rootURL = rootURL
        self.notes = notes.sorted {
            $0.modifiedAt > $1.modifiedAt
        }
        self.attachments = attachments

        var noteLookup = [String: String]()
        for note in notes {
            for key in note.lookupKeys {
                noteLookup[key] = note.id
            }
        }
        self.noteLookup = noteLookup
    }

    func note(withID id: String) -> VaultNote? {
        notes.first(where: { $0.id == id })
    }

    func resolveNoteID(for target: String) -> String? {
        noteLookup[normalizeVaultReference(target)]
    }

    func attachment(for path: String) -> VaultAttachment? {
        attachments[normalizeVaultReference(path)]
    }
}

struct VaultNote: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let relativePath: String
    let previewText: String
    let tags: [String]
    let outboundLinks: [String]
    let blocks: [RenderBlock]
    let wordCount: Int
    let readingTimeMinutes: Int
    let modifiedAt: Date

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

struct VaultAttachment: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case image
        case pdf
        case audio
        case video
        case other
    }

    let relativePath: String
    let url: URL
    let kind: Kind
}

enum RenderBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case quote(text: String)
    case callout(kind: CalloutKind, title: String, body: String)
    case code(language: String?, code: String)
    case image(path: String, alt: String?)
    case divider
}

enum CalloutKind: String, Hashable, Sendable {
    case note
    case info
    case tip
    case warning
    case danger
    case success

    var label: String {
        rawValue.capitalized
    }
}

func normalizeVaultReference(_ reference: String) -> String {
    let trimmed = reference
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\", with: "/")
        .replacingOccurrences(of: ".md", with: "", options: .caseInsensitive)
        .lowercased()
    return trimmed
}
