import Foundation
import ObviewerFixtureSupport

struct CLIOptions {
    let outputURL: URL
    let profile: DemoVaultProfile
}

enum FixtureToolError: LocalizedError {
    case missingOutput
    case unsupportedArgument(String)
    case missingValue(String)
    case unknownProfile(String)

    var errorDescription: String? {
        switch self {
        case .missingOutput:
            return "Pass --output /path/to/vault."
        case .unsupportedArgument(let argument):
            return "Unsupported argument: \(argument)"
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .unknownProfile(let profile):
            return "Unknown profile '\(profile)'. Use smoke, showcase, or integration."
        }
    }
}

do {
    let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    let manifest = try DemoVaultBuilder.populate(at: options.outputURL, profile: options.profile)
    print("Generated demo vault at \(manifest.rootURL.path)")
    print("Notes: \(manifest.noteCount)")
    print("Attachments: \(manifest.attachmentCount)")
    print("Home note: \(manifest.homeNoteID)")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}

private func parseArguments(_ arguments: [String]) throws -> CLIOptions {
    var outputPath: String?
    var profile = DemoVaultProfile.showcase

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--output":
            index += 1
            guard index < arguments.count else {
                throw FixtureToolError.missingValue(argument)
            }
            outputPath = arguments[index]
        case "--profile":
            index += 1
            guard index < arguments.count else {
                throw FixtureToolError.missingValue(argument)
            }
            profile = try profileValue(for: arguments[index])
        default:
            throw FixtureToolError.unsupportedArgument(argument)
        }
        index += 1
    }

    guard let outputPath else {
        throw FixtureToolError.missingOutput
    }

    return CLIOptions(
        outputURL: URL(fileURLWithPath: outputPath, isDirectory: true),
        profile: profile
    )
}

private func profileValue(for value: String) throws -> DemoVaultProfile {
    switch value.lowercased() {
    case "smoke":
        return .smoke
    case "showcase":
        return .showcase
    case "integration":
        return .integration
    default:
        throw FixtureToolError.unknownProfile(value)
    }
}
