import Foundation

@MainActor
protocol VaultBookmarkStoring {
    func save(url: URL) throws
    func restore() throws -> URL?
}

@MainActor
struct BookmarkStore: VaultBookmarkStoring {
    private let key = "vault-bookmark"

    func save(url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
    }

    func restore() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try save(url: url)
        }

        return url
    }
}
