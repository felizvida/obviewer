import Foundation

@MainActor
protocol SecurityScopeManaging {
    func activate(url: URL)
}

@MainActor
final class SecurityScopedAccessController: SecurityScopeManaging {
    private var activeScopedURL: URL?

    func activate(url: URL) {
        let standardized = url.standardizedFileURL
        if activeScopedURL?.standardizedFileURL == standardized {
            return
        }

        activeScopedURL?.stopAccessingSecurityScopedResource()
        _ = standardized.startAccessingSecurityScopedResource()
        activeScopedURL = standardized
    }

    deinit {
        activeScopedURL?.stopAccessingSecurityScopedResource()
    }
}
