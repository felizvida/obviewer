import Foundation

public protocol VaultLoading: Sendable {
    func loadVault(at url: URL) throws -> VaultSnapshot
}
