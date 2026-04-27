import Foundation
import ObviewerCore
import CryptoKit

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
    private let schemaVersion = 3
    private let supportedSchemaVersions: Set<Int> = [1, 2, 3]

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
        for fileURL in candidateCacheFileURLs(for: vaultURL) {
            guard let data = try? Data(contentsOf: fileURL) else {
                continue
            }

            do {
                let payload = try PropertyListDecoder().decode(CachedVaultSeed.self, from: data)
                guard supportedSchemaVersions.contains(payload.schemaVersion) else {
                    removeSeedSnapshot(for: vaultURL)
                    return nil
                }

                guard payload.rootPath == normalizedPath(for: vaultURL) else {
                    removeSeedSnapshot(for: vaultURL)
                    return nil
                }

                if fileURL != cacheFileURL(for: vaultURL) {
                    saveSeedSnapshot(
                        VaultSnapshot(
                            rootURL: vaultURL,
                            notes: payload.notes,
                            attachments: payload.attachments,
                            indexManifest: payload.indexManifest
                                ?? VaultIndexManifest(notes: payload.notes, attachments: payload.attachments),
                            persistentIndex: payload.persistentIndex
                        )
                    )
                    try? FileManager.default.removeItem(at: fileURL)
                }

                return VaultSnapshot(
                    rootURL: vaultURL,
                    notes: payload.notes,
                    attachments: payload.attachments,
                    indexManifest: payload.indexManifest
                        ?? VaultIndexManifest(notes: payload.notes, attachments: payload.attachments),
                    persistentIndex: payload.persistentIndex
                )
            } catch {
                removeSeedSnapshot(for: vaultURL)
                return nil
            }
        }

        return nil
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
                attachments: snapshot.attachments,
                indexManifest: snapshot.indexManifest,
                persistentIndex: snapshot.persistentIndex
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(payload)
            try data.write(to: cacheFileURL(for: snapshot.rootURL), options: .atomic)
            let legacyURL = legacyCacheFileURL(for: snapshot.rootURL)
            if legacyURL != cacheFileURL(for: snapshot.rootURL) {
                try? FileManager.default.removeItem(at: legacyURL)
            }
        } catch {
            // Cache writes are opportunistic and must never fail the load path.
        }
    }

    func removeSeedSnapshot(for vaultURL: URL) {
        for fileURL in candidateCacheFileURLs(for: vaultURL) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func cacheFileURL(for vaultURL: URL) -> URL {
        cachesRootURL.appending(path: "\(cacheKey(for: vaultURL)).plist")
    }

    private func cacheKey(for vaultURL: URL) -> String {
        let digest = SHA256.hash(data: Data(normalizedPath(for: vaultURL).utf8))
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return "vault-\(hexDigest)"
    }

    private func legacyCacheFileURL(for vaultURL: URL) -> URL {
        cachesRootURL.appending(path: "\(legacyCacheKey(for: vaultURL)).plist")
    }

    private func legacyCacheKey(for vaultURL: URL) -> String {
        let data = Data(normalizedPath(for: vaultURL).utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func candidateCacheFileURLs(for vaultURL: URL) -> [URL] {
        let primaryURL = cacheFileURL(for: vaultURL)
        let legacyURL = legacyCacheFileURL(for: vaultURL)
        if legacyURL == primaryURL {
            return [primaryURL]
        }
        return [primaryURL, legacyURL]
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
    let indexManifest: VaultIndexManifest?
    let persistentIndex: VaultPersistentIndex?
}
