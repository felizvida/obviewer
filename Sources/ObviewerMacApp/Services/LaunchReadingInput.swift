import Foundation
import ObviewerCore

public struct LaunchReadingInputRequest: Equatable, Sendable {
    public let url: URL
    public let preferredProfile: ReadingProfile?

    public init(url: URL, preferredProfile: ReadingProfile?) {
        self.url = url.standardizedFileURL
        self.preferredProfile = preferredProfile
    }
}

public enum LaunchReadingInputParser {
    public static func parse(
        _ arguments: [String],
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) -> LaunchReadingInputRequest? {
        var preferredProfile: ReadingProfile?
        var pendingPathFromOpenFlag = false
        var pendingProfileValue = false
        var positionalPath: String?
        var shouldTreatRemainingAsPath = false

        for argument in arguments {
            if pendingProfileValue {
                preferredProfile = parseProfile(argument)
                pendingProfileValue = false
                continue
            }

            if pendingPathFromOpenFlag {
                positionalPath = argument
                pendingPathFromOpenFlag = false
                continue
            }

            if shouldTreatRemainingAsPath {
                positionalPath = argument
                break
            }

            switch argument {
            case "--":
                shouldTreatRemainingAsPath = true
            case "--open":
                pendingPathFromOpenFlag = true
            case "--markdown":
                preferredProfile = .markdown
            case "--obsidian":
                preferredProfile = .obsidian
            case "--profile=markdown":
                preferredProfile = .markdown
            case "--profile=obsidian":
                preferredProfile = .obsidian
            case "--profile":
                pendingProfileValue = true
            default:
                if argument.hasPrefix("-psn_") {
                    continue
                }

                if argument.hasPrefix("--profile=") {
                    preferredProfile = parseProfile(argument.dropFirst("--profile=".count))
                    continue
                }

                if argument.hasPrefix("-") {
                    continue
                }

                positionalPath = argument
            }

            if positionalPath != nil {
                break
            }
        }

        guard let positionalPath else { return nil }
        return LaunchReadingInputRequest(
            url: fileURL(for: positionalPath, relativeTo: currentDirectoryURL),
            preferredProfile: preferredProfile
        )
    }

    private static func parseProfile<S: StringProtocol>(_ value: S) -> ReadingProfile? {
        switch value.lowercased() {
        case "markdown", "md":
            return .markdown
        case "obsidian", "vault":
            return .obsidian
        default:
            return nil
        }
    }

    private static func fileURL(for path: String, relativeTo currentDirectoryURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        if path == "~" || path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
                .standardizedFileURL
        }

        return URL(fileURLWithPath: path, relativeTo: currentDirectoryURL).standardizedFileURL
    }
}
