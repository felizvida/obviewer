import Foundation
import ObviewerCore
import ObviewerFixtureSupport

@main
struct ObviewerBenchmarkTool {
    static func main() throws {
        let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
        let report = try BenchmarkRunner().run(options: options)
        let renderedOutput = try serialize(report: report, format: options.format)

        if let outputURL = options.outputURL {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try renderedOutput.write(to: outputURL, atomically: true, encoding: .utf8)
            print("Wrote benchmark report to \(outputURL.path)")
        } else {
            print(renderedOutput)
        }

        if let budget = try options.loadBudget() {
            try budget.validate(report: report)
            print("Benchmark budgets satisfied.")
        }
    }

    private static func serialize(report: BenchmarkReport, format: CLIOptions.OutputFormat) throws -> String {
        switch format {
        case .text:
            return report.renderedText
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(decoding: try encoder.encode(report), as: UTF8.self)
        }
    }
}

private extension FileManager {
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
    }
}

private struct CLIOptions {
    enum OutputFormat: String {
        case text
        case json
    }

    let format: OutputFormat
    let profile: DemoVaultProfile
    let existingVaultURL: URL?
    let outputURL: URL?
    let budgetURL: URL?

    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var format = OutputFormat.text
        var profile = DemoVaultProfile.benchmark
        var existingVaultURL: URL?
        var outputURL: URL?
        var budgetURL: URL?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--format":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                guard let outputFormat = OutputFormat(rawValue: arguments[index].lowercased()) else {
                    throw CLIError.invalidFormat(arguments[index])
                }
                format = outputFormat
            case "--profile":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                profile = try parseProfile(arguments[index])
            case "--vault":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                existingVaultURL = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                outputURL = URL(fileURLWithPath: arguments[index])
            case "--budget":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                budgetURL = URL(fileURLWithPath: arguments[index])
            default:
                throw CLIError.unsupportedArgument(argument)
            }
            index += 1
        }

        return CLIOptions(
            format: format,
            profile: profile,
            existingVaultURL: existingVaultURL,
            outputURL: outputURL,
            budgetURL: budgetURL
        )
    }

    private static func parseProfile(_ value: String) throws -> DemoVaultProfile {
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

    func loadBudget() throws -> BenchmarkBudget? {
        guard let budgetURL else {
            return nil
        }

        do {
            let data = try Data(contentsOf: budgetURL)
            return try JSONDecoder().decode(BenchmarkBudget.self, from: data)
        } catch {
            throw CLIError.invalidBudget("\(budgetURL.path): \(error.localizedDescription)")
        }
    }
}

private enum CLIError: LocalizedError {
    case missingValue(String)
    case unsupportedArgument(String)
    case invalidFormat(String)
    case unknownProfile(String)
    case unreadableVault(String)
    case invalidBudget(String)
    case budgetFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .unsupportedArgument(let argument):
            return "Unsupported argument: \(argument)"
        case .invalidFormat(let format):
            return "Unknown format '\(format)'. Use text or json."
        case .unknownProfile(let value):
            return "Unknown profile '\(value)'. Use smoke, showcase, integration, or benchmark."
        case .unreadableVault(let path):
            return "Vault does not exist or is not a directory: \(path)"
        case .invalidBudget(let description):
            return "Could not load benchmark budget: \(description)"
        case .budgetFailed(let details):
            return "Benchmark budgets failed:\n\(details)"
        }
    }
}

private struct BenchmarkRunner {
    private let reader = VaultReader()

    func run(options: CLIOptions) throws -> BenchmarkReport {
        if let existingVaultURL = options.existingVaultURL {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: existingVaultURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw CLIError.unreadableVault(existingVaultURL.path)
            }

            return try measureVault(
                at: existingVaultURL,
                source: "existing-vault",
                profileName: nil,
                selectiveReloadPath: nil
            )
        }

        let fixture = try TemporaryDemoVault(profile: options.profile)
        defer { fixture.cleanup() }

        return try measureVault(
            at: fixture.rootURL,
            source: "generated-fixture",
            profileName: options.profile.name,
            selectiveReloadPath: fixture.manifest.alphaOverviewNoteID
        )
    }

    private func measureVault(
        at rootURL: URL,
        source: String,
        profileName: String?,
        selectiveReloadPath: String?
    ) throws -> BenchmarkReport {
        let (coldSnapshot, coldLoadMs) = try measure {
            try reader.loadVault(at: rootURL)
        }

        let (warmSnapshot, warmReloadMs) = try measure {
            try reader.reloadVault(at: rootURL, previousSnapshot: coldSnapshot)
        }

        let searchQueries = ["#reader", "Daily", "Architecture", "Platform Experience"]
        let (searchResults, searchMs) = measure {
            searchQueries.map { query in
                SearchBenchmarkResult(query: query, matchCount: warmSnapshot.searchNotes(matching: query).count)
            }
        }

        let allNoteIDs = Set(warmSnapshot.notes.map(\.id))
        let (globalSubgraph, globalGraphMs) = measure {
            warmSnapshot.noteGraph.globalSubgraph(visibleNoteIDs: allNoteIDs)
        }

        let localGraphMs: Double
        if let centerID = warmSnapshot.notes.first?.id {
            let (_, elapsedMs) = measure {
                warmSnapshot.noteGraph.localSubgraph(around: centerID)
            }
            localGraphMs = elapsedMs
        } else {
            localGraphMs = 0
        }

        var timings = [
            BenchmarkTiming(name: "cold-load", milliseconds: coldLoadMs),
            BenchmarkTiming(name: "warm-reload", milliseconds: warmReloadMs),
            BenchmarkTiming(name: "search-pass", milliseconds: searchMs),
            BenchmarkTiming(name: "graph-global-subgraph", milliseconds: globalGraphMs),
            BenchmarkTiming(name: "graph-local-subgraph", milliseconds: localGraphMs),
        ]

        if let selectiveReloadPath {
            try appendBenchmarkMarker(to: selectiveReloadPath, in: rootURL)
            let (_, selectiveReloadMs) = try measure {
                try reader.reloadVault(
                    at: rootURL,
                    previousSnapshot: warmSnapshot,
                    changes: VaultReloadChanges(modifiedPaths: [selectiveReloadPath])
                )
            }
            timings.append(BenchmarkTiming(name: "selective-reload", milliseconds: selectiveReloadMs))
        }

        return BenchmarkReport(
            source: source,
            profileName: profileName,
            rootPath: rootURL.path,
            diagnostics: warmSnapshot.indexDiagnostics(topFolderCount: 6),
            timings: timings,
            searchResults: searchResults,
            graphNodeCount: globalSubgraph.nodes.count,
            graphEdgeCount: globalSubgraph.edges.count
        )
    }

    private func measure<T>(_ work: () throws -> T) rethrows -> (T, Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try work()
        let end = DispatchTime.now().uptimeNanoseconds
        let elapsedMs = Double(end - start) / 1_000_000
        return (value, elapsedMs)
    }

    private func appendBenchmarkMarker(to relativePath: String, in rootURL: URL) throws {
        let noteURL = rootURL.appending(path: relativePath)
        let existing = try String(contentsOf: noteURL, encoding: .utf8)
        let updated = existing + "\n\nBenchmark marker at \(ISO8601DateFormatter().string(from: Date()))\n"
        try updated.write(to: noteURL, atomically: true, encoding: .utf8)
    }
}

private struct BenchmarkReport: Codable {
    let source: String
    let profileName: String?
    let rootPath: String
    let diagnostics: VaultIndexDiagnostics
    let timings: [BenchmarkTiming]
    let searchResults: [SearchBenchmarkResult]
    let graphNodeCount: Int
    let graphEdgeCount: Int

    func timing(named name: String) -> BenchmarkTiming? {
        timings.first { $0.name == name }
    }

    var renderedText: String {
        var lines = [String]()
        lines.append("Obviewer Vault Benchmark")
        lines.append("========================")
        lines.append("Source: \(source)\(profileName.map { " (\($0))" } ?? "")")
        lines.append("Vault: \(rootPath)")
        lines.append("")
        lines.append("Index Diagnostics")
        lines.append("- Files: \(diagnostics.totalFileCount) total (\(diagnostics.noteCount) notes, \(diagnostics.attachmentCount) attachments)")
        lines.append("- Folders: \(diagnostics.folderCount)")
        lines.append("- Unique tags: \(diagnostics.uniqueTagCount)")
        lines.append("- Graph: \(graphNodeCount) nodes, \(graphEdgeCount) edges")
        lines.append("- Average words per note: \(formatDecimal(diagnostics.averageWordsPerNote))")
        lines.append("- Average outbound links per note: \(formatDecimal(diagnostics.averageOutboundLinksPerNote))")

        if diagnostics.attachmentKindCounts.isEmpty == false {
            lines.append("")
            lines.append("Attachment Mix")
            for summary in diagnostics.attachmentKindCounts {
                lines.append("- \(summary.kind.rawValue): \(summary.count)")
            }
        }

        if diagnostics.largestFolders.isEmpty == false {
            lines.append("")
            lines.append("Largest Folders")
            for folder in diagnostics.largestFolders {
                lines.append("- \(folder.displayName): \(folder.totalFileCount) files (\(folder.noteCount) notes, \(folder.attachmentCount) attachments)")
            }
        }

        lines.append("")
        lines.append("Timings")
        for timing in timings {
            lines.append("- \(timing.name): \(formatDecimal(timing.milliseconds)) ms")
        }

        if searchResults.isEmpty == false {
            lines.append("")
            lines.append("Sample Query Matches")
            for result in searchResults {
                lines.append("- \(result.query): \(result.matchCount)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct BenchmarkTiming: Codable {
    let name: String
    let milliseconds: Double
}

private struct SearchBenchmarkResult: Codable {
    let query: String
    let matchCount: Int
}

private struct BenchmarkBudget: Codable {
    let name: String?
    let minimumNoteCount: Int?
    let minimumAttachmentCount: Int?
    let minimumGraphNodeCount: Int?
    let minimumGraphEdgeCount: Int?
    let maximumTimingsMilliseconds: [String: Double]

    func validate(report: BenchmarkReport) throws {
        var violations = [String]()

        if let minimumNoteCount, report.diagnostics.noteCount < minimumNoteCount {
            violations.append("Expected at least \(minimumNoteCount) notes, found \(report.diagnostics.noteCount).")
        }

        if let minimumAttachmentCount, report.diagnostics.attachmentCount < minimumAttachmentCount {
            violations.append("Expected at least \(minimumAttachmentCount) attachments, found \(report.diagnostics.attachmentCount).")
        }

        if let minimumGraphNodeCount, report.graphNodeCount < minimumGraphNodeCount {
            violations.append("Expected at least \(minimumGraphNodeCount) graph nodes, found \(report.graphNodeCount).")
        }

        if let minimumGraphEdgeCount, report.graphEdgeCount < minimumGraphEdgeCount {
            violations.append("Expected at least \(minimumGraphEdgeCount) graph edges, found \(report.graphEdgeCount).")
        }

        for timingName in maximumTimingsMilliseconds.keys.sorted() {
            guard let maximumMilliseconds = maximumTimingsMilliseconds[timingName] else {
                continue
            }

            guard let timing = report.timing(named: timingName) else {
                violations.append("Missing timing '\(timingName)' in benchmark report.")
                continue
            }

            if timing.milliseconds > maximumMilliseconds {
                violations.append(
                    "Timing '\(timingName)' exceeded budget: \(formatDecimal(timing.milliseconds)) ms > \(formatDecimal(maximumMilliseconds)) ms."
                )
            }
        }

        if violations.isEmpty == false {
            throw CLIError.budgetFailed(violations.joined(separator: "\n"))
        }
    }

    private func formatDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
