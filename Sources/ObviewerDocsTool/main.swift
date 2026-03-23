import Foundation
import ObviewerFixtureSupport
import ObviewerMacApp

@main
struct ObviewerDocsTool {
    static func main() async throws {
        let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
        let fixture = try TemporaryDemoVault(profile: options.profile)
        defer { fixture.cleanup() }

        let specs = [
            DocumentationScreenshotSpec(
                fileName: "visual-tour-library-home.png",
                title: "Library Overview",
                selectedNoteID: fixture.manifest.homeNoteID
            ),
            DocumentationScreenshotSpec(
                fileName: "visual-tour-project-overview.png",
                title: "Project Reading View",
                selectedNoteID: fixture.manifest.alphaOverviewNoteID
            ),
            DocumentationScreenshotSpec(
                fileName: "visual-tour-tag-search.png",
                title: "Tag-Focused Search",
                selectedNoteID: fixture.manifest.alphaOverviewNoteID,
                searchText: "#alpha"
            ),
        ]

        try await DocumentationScreenshotRenderer.render(
            vaultURL: fixture.rootURL,
            specs: specs,
            outputDirectory: options.outputURL
        )

        print("Generated \(specs.count) screenshots in \(options.outputURL.path)")
    }
}

private struct CLIOptions {
    let outputURL: URL
    let profile: DemoVaultProfile

    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var outputPath = "docs/images"
        var profile = DemoVaultProfile.showcase

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                outputPath = arguments[index]
            case "--profile":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                profile = try parseProfile(arguments[index])
            default:
                throw CLIError.unsupportedArgument(argument)
            }
            index += 1
        }

        return CLIOptions(
            outputURL: URL(fileURLWithPath: outputPath, isDirectory: true),
            profile: profile
        )
    }

    static func parseProfile(_ value: String) throws -> DemoVaultProfile {
        switch value.lowercased() {
        case "smoke":
            return .smoke
        case "showcase":
            return .showcase
        case "integration":
            return .integration
        case "benchmark":
            return .benchmark
        default:
            throw CLIError.unknownProfile(value)
        }
    }
}

private enum CLIError: LocalizedError {
    case missingValue(String)
    case unsupportedArgument(String)
    case unknownProfile(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .unsupportedArgument(let argument):
            return "Unsupported argument: \(argument)"
        case .unknownProfile(let value):
            return "Unknown profile '\(value)'. Use smoke, showcase, integration, or benchmark."
        }
    }
}
