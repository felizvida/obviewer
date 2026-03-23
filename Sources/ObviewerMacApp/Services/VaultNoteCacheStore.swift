import Foundation
import ObviewerCore

protocol VaultNoteCaching: Sendable {
    func loadSeedSnapshot(for vaultURL: URL) -> VaultSnapshot?
    func saveSeedSnapshot(_ snapshot: VaultSnapshot)
    func removeSeedSnapshot(for vaultURL: URL)
}

struct NullVaultNoteCache: VaultNoteCaching {
    func loadSeedSnapshot(for vaultURL: URL) -> VaultSnapshot? {
        nil
    }

    func saveSeedSnapshot(_ snapshot: VaultSnapshot) {}

    func removeSeedSnapshot(for vaultURL: URL) {}
}

struct VaultNoteCacheStore: VaultNoteCaching {
    private let cachesRootURL: URL
    private let schemaVersion = 1

    init(cachesRootURL: URL? = nil) {
        let fileManager = FileManager.default
        if let cachesRootURL {
            self.cachesRootURL = cachesRootURL
        } else {
            let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.cachesRootURL = baseURL
                .appending(path: "com.felizvida.obviewer")
                .appending(path: "vault-note-cache")
        }
    }

    func loadSeedSnapshot(for vaultURL: URL) -> VaultSnapshot? {
        let fileURL = cacheFileURL(for: vaultURL)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        do {
            let payload = try PropertyListDecoder().decode(CachedVaultSeed.self, from: data)
            guard payload.schemaVersion == schemaVersion else {
                removeSeedSnapshot(for: vaultURL)
                return nil
            }

            guard payload.rootPath == normalizedPath(for: vaultURL) else {
                removeSeedSnapshot(for: vaultURL)
                return nil
            }

            return VaultSnapshot(rootURL: vaultURL, notes: payload.notes, attachments: payload.attachments)
        } catch {
            removeSeedSnapshot(for: vaultURL)
            return nil
        }
    }

    func saveSeedSnapshot(_ snapshot: VaultSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: cachesRootURL,
                withIntermediateDirectories: true
            )

            let payload = CachedVaultSeed(
                schemaVersion: schemaVersion,
                rootPath: normalizedPath(for: snapshot.rootURL),
                notes: snapshot.notes,
                attachments: snapshot.attachments
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(payload)
            try data.write(to: cacheFileURL(for: snapshot.rootURL), options: .atomic)
        } catch {
            // Cache writes are opportunistic and must never fail the load path.
        }
    }

    func removeSeedSnapshot(for vaultURL: URL) {
        try? FileManager.default.removeItem(at: cacheFileURL(for: vaultURL))
    }

    private func cacheFileURL(for vaultURL: URL) -> URL {
        cachesRootURL.appending(path: "\(cacheKey(for: vaultURL)).plist")
    }

    private func cacheKey(for vaultURL: URL) -> String {
        let data = Data(normalizedPath(for: vaultURL).utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func normalizedPath(for vaultURL: URL) -> String {
        vaultURL.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private struct CachedVaultSeed: Codable {
    let schemaVersion: Int
    let rootPath: String
    let notes: [VaultNote]
    let attachments: [VaultAttachment]
}
