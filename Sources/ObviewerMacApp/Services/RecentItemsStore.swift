import Foundation

/// Recently opened files and folders, stored as read-only security-scoped bookmarks.
@MainActor
final class RecentItemsStore: ObservableObject {
    static let shared = RecentItemsStore()
    static let maximumCount = 12

    struct Item: Identifiable, Equatable {
        let url: URL
        let bookmark: Data
        var id: String { url.path }
        var displayName: String { url.lastPathComponent }
    }

    @Published private(set) var items: [Item] = []
    private let defaultsKey = "obviewer.recentItems"

    init() {
        load()
    }

    func record(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: BookmarkStore.bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        var updated = items.filter { $0.url.standardizedFileURL != url.standardizedFileURL }
        updated.insert(Item(url: url, bookmark: bookmark), at: 0)
        items = Array(updated.prefix(Self.maximumCount))
        save()
    }

    /// Resolves a recent item, starting security-scoped access. The caller keeps access for the window's lifetime.
    func resolve(_ item: Item) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: item.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            remove(item)
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        if isStale { record(url) }
        return url
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] else { return }
        items = stored.compactMap { data in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            return Item(url: url, bookmark: data)
        }
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.bookmark), forKey: defaultsKey)
    }
}
