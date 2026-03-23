import CoreGraphics
import Foundation

public struct DemoVaultProfile: Hashable, Sendable {
    public let name: String
    public let sprintCountPerProject: Int
    public let decisionCountPerProject: Int
    public let architectureNoteCount: Int
    public let swiftNoteCount: Int
    public let journalEntryCount: Int
    public let meetingWeekCount: Int
    public let galleryImageCount: Int

    public init(
        name: String,
        sprintCountPerProject: Int,
        decisionCountPerProject: Int,
        architectureNoteCount: Int,
        swiftNoteCount: Int,
        journalEntryCount: Int,
        meetingWeekCount: Int,
        galleryImageCount: Int
    ) {
        self.name = name
        self.sprintCountPerProject = sprintCountPerProject
        self.decisionCountPerProject = decisionCountPerProject
        self.architectureNoteCount = architectureNoteCount
        self.swiftNoteCount = swiftNoteCount
        self.journalEntryCount = journalEntryCount
        self.meetingWeekCount = meetingWeekCount
        self.galleryImageCount = galleryImageCount
    }

    public static let smoke = DemoVaultProfile(
        name: "smoke",
        sprintCountPerProject: 4,
        decisionCountPerProject: 3,
        architectureNoteCount: 8,
        swiftNoteCount: 8,
        journalEntryCount: 10,
        meetingWeekCount: 4,
        galleryImageCount: 3
    )

    public static let showcase = DemoVaultProfile(
        name: "showcase",
        sprintCountPerProject: 12,
        decisionCountPerProject: 8,
        architectureNoteCount: 12,
        swiftNoteCount: 12,
        journalEntryCount: 21,
        meetingWeekCount: 6,
        galleryImageCount: 6
    )

    public static let integration = DemoVaultProfile(
        name: "integration",
        sprintCountPerProject: 18,
        decisionCountPerProject: 12,
        architectureNoteCount: 20,
        swiftNoteCount: 20,
        journalEntryCount: 45,
        meetingWeekCount: 8,
        galleryImageCount: 6
    )

    public static let benchmark = DemoVaultProfile(
        name: "benchmark",
        sprintCountPerProject: 40,
        decisionCountPerProject: 24,
        architectureNoteCount: 48,
        swiftNoteCount: 48,
        journalEntryCount: 180,
        meetingWeekCount: 20,
        galleryImageCount: 12
    )
}

public struct DemoVaultManifest: Hashable, Sendable {
    public let rootURL: URL
    public let noteCount: Int
    public let attachmentCount: Int
    public let homeNoteID: String
    public let architectureIndexNoteID: String
    public let alphaOverviewNoteID: String
    public let alphaDailyNoteID: String
    public let betaOverviewNoteID: String
    public let betaDailyNoteID: String
    public let alphaCoverAttachmentPath: String
    public let betaCoverAttachmentPath: String
    public let operationsManualAttachmentPath: String
    public let firstJournalNoteID: String
}

public final class TemporaryDemoVault {
    public let rootURL: URL
    public let manifest: DemoVaultManifest

    public init(profile: DemoVaultProfile = .integration) throws {
        let baseURL = FileManager.default.temporaryDirectory
        rootURL = baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        manifest = try DemoVaultBuilder.populate(at: rootURL, profile: profile)
    }

    public func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

public enum DemoVaultBuilder {
    private static let projects = ["Alpha", "Beta", "Gamma"]

    @discardableResult
    public static func populate(
        at rootURL: URL,
        profile: DemoVaultProfile = .showcase
    ) throws -> DemoVaultManifest {
        try ensureEmptyDirectory(at: rootURL)

        var writer = VaultFixtureWriter(rootURL: rootURL)

        try writer.writeAttachment("Assets/Images/shared-cover.png", data: makePNGData())
        for imageIndex in 1...profile.galleryImageCount {
            try writer.writeAttachment(
                "Assets/Images/dashboard-\(padded(imageIndex)).png",
                data: makePNGData()
            )
        }
        try writer.writeAttachment("Assets/Documents/operations-manual.pdf", data: makeBlankPDFData())
        try writer.writeAttachment(
            "Assets/Documents/reader-notes.txt",
            data: Data("Synthetic Obsidian vault for reader verification.\n".utf8)
        )
        try writer.writeAttachment(
            "Assets/Audio/daily-standup.m4a",
            data: Data("placeholder-audio".utf8)
        )
        try writer.writeAttachment(
            "Assets/Video/release-walkthrough.mp4",
            data: Data("placeholder-video".utf8)
        )

        for project in projects {
            let slug = lowercase(project)
            try writer.writeAttachment("Projects/\(project)/cover.png", data: makePNGData())
            try writer.writeAttachment(
                "Projects/\(project)/spec.pdf",
                data: makeBlankPDFData()
            )

            try writer.writeNote("Projects/\(project)/Index.md", contents: projectIndexNote(project: project, slug: slug))
            try writer.writeNote("Projects/\(project)/Daily.md", contents: projectDailyNote(project: project, slug: slug))
            try writer.writeNote("Projects/\(project)/Roadmap.md", contents: projectRoadmapNote(project: project, slug: slug))
            try writer.writeNote("Projects/\(project)/Overview.md", contents: projectOverviewNote(project: project, slug: slug))

            for sprintIndex in 1...profile.sprintCountPerProject {
                try writer.writeNote(
                    "Projects/\(project)/Sprints/Sprint \(padded(sprintIndex)).md",
                    contents: sprintNote(project: project, slug: slug, sprintIndex: sprintIndex)
                )
            }

            for decisionIndex in 1...profile.decisionCountPerProject {
                try writer.writeNote(
                    "Projects/\(project)/Notes/Decision \(padded(decisionIndex)).md",
                    contents: decisionNote(project: project, slug: slug, decisionIndex: decisionIndex)
                )
            }
        }

        try writer.writeNote("Knowledge/Architecture/Index.md", contents: architectureIndexNote())
        for noteIndex in 1...profile.architectureNoteCount {
            try writer.writeNote(
                "Knowledge/Architecture/Pattern \(padded(noteIndex)).md",
                contents: architecturePatternNote(noteIndex: noteIndex)
            )
        }

        try writer.writeNote("Knowledge/Swift/Index.md", contents: swiftIndexNote())
        for noteIndex in 1...profile.swiftNoteCount {
            try writer.writeNote(
                "Knowledge/Swift/Technique \(padded(noteIndex)).md",
                contents: swiftTechniqueNote(noteIndex: noteIndex)
            )
        }

        for journalIndex in 1...profile.journalEntryCount {
            let month = 3 + ((journalIndex - 1) / 28)
            let day = ((journalIndex - 1) % 28) + 1
            let monthValue = padded(month)
            let dayValue = padded(day)
            try writer.writeNote(
                "Journal/2026/\(monthValue)/2026-\(monthValue)-\(dayValue).md",
                contents: journalNote(monthValue: monthValue, dayValue: dayValue, project: projects[(journalIndex - 1) % projects.count])
            )
        }

        for meetingIndex in 1...profile.meetingWeekCount {
            try writer.writeNote(
                "Meetings/2026/Wk\(padded(meetingIndex))/Weekly Sync.md",
                contents: weeklySyncNote(week: meetingIndex, project: projects[(meetingIndex - 1) % projects.count])
            )
        }

        try writer.writeNote("Inbox.md", contents: inboxNote())
        try writer.writeNote("Style Guide.md", contents: styleGuideNote())
        try writer.writeNote("Reader Playground.md", contents: readerPlaygroundNote())
        try writer.writeNote("Home.md", contents: homeNote())

        return DemoVaultManifest(
            rootURL: rootURL,
            noteCount: writer.noteCount,
            attachmentCount: writer.attachmentCount,
            homeNoteID: "Home.md",
            architectureIndexNoteID: "Knowledge/Architecture/Index.md",
            alphaOverviewNoteID: "Projects/Alpha/Overview.md",
            alphaDailyNoteID: "Projects/Alpha/Daily.md",
            betaOverviewNoteID: "Projects/Beta/Overview.md",
            betaDailyNoteID: "Projects/Beta/Daily.md",
            alphaCoverAttachmentPath: "Projects/Alpha/cover.png",
            betaCoverAttachmentPath: "Projects/Beta/cover.png",
            operationsManualAttachmentPath: "Assets/Documents/operations-manual.pdf",
            firstJournalNoteID: "Journal/2026/03/2026-03-01.md"
        )
    }
}

public enum DemoVaultBuilderError: LocalizedError {
    case outputDirectoryAlreadyContainsFiles(String)

    public var errorDescription: String? {
        switch self {
        case .outputDirectoryAlreadyContainsFiles(let path):
            return "Refusing to overwrite non-empty directory at \(path)."
        }
    }
}

private struct VaultFixtureWriter {
    let rootURL: URL
    private(set) var noteCount = 0
    private(set) var attachmentCount = 0
    private var modificationIndex = 0

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    mutating func writeNote(_ relativePath: String, contents: String) throws {
        try writeFile(relativePath, data: Data(contents.utf8))
        noteCount += 1
    }

    mutating func writeAttachment(_ relativePath: String, data: Data) throws {
        try writeFile(relativePath, data: data)
        attachmentCount += 1
    }

    private mutating func writeFile(_ relativePath: String, data: Data) throws {
        let fileURL = rootURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: fileURL)
        modificationIndex += 1
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_710_000_000 + Double(modificationIndex))],
            ofItemAtPath: fileURL.path
        )
    }
}

private func ensureEmptyDirectory(at rootURL: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: rootURL.path) {
        let contents = try fileManager.contentsOfDirectory(atPath: rootURL.path)
        guard contents.isEmpty else {
            throw DemoVaultBuilderError.outputDirectoryAlreadyContainsFiles(rootURL.path)
        }
    } else {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

private func homeNote() -> String {
    """
    ---
    title: Obviewer Demo Vault
    aliases: ["Demo Home", "Vault Landing"]
    tags:
      - reader
      - demo
      - qa
    status: curated
    owner: Platform Experience
    updated: 2026-03-23
    ---
    # Obviewer Demo Vault

    Welcome to a synthetic vault built to exercise the reader at scale. This page links into #reader, #demo, and #qa workflows.

    > [!note] Reader Checklist
    > Start with [[Projects/Alpha/Overview]], compare it with [[Projects/Beta/Overview]], and then jump into [[Knowledge/Architecture/Index]].

    ## Highlights

    Review [Architecture Patterns](Knowledge/Architecture/Index.md#Patterns), open the [Operations Manual](Assets/Documents/operations-manual.pdf), and inspect the inline media ![[Assets/Images/shared-cover.png|Shared cover]].

    ![[Assets/Images/shared-cover.png]]

    | Area | What To Verify |
    | --- | --- |
    | Projects | Duplicate note routing with `Daily.md` and `Index.md` |
    | Attachments | Folder-local `cover.png` versus shared assets |
    | Reader | Tables, callouts, code, images, anchors, and tags |

    ## Reader Checklist

    - Open [[Reader Playground]]
    - Search for #alpha
    - Navigate to [[Projects/Alpha/Daily]]
    - Open [[Journal/2026/03/2026-03-01]]

    ```swift
    let promise = "read-only"
    print(promise)
    ```
    """
}

private func inboxNote() -> String {
    """
    # Inbox

    This root note exists to ensure Vault Root grouping is visible in the sidebar.

    - Review #triage items
    - Compare [[Projects/Alpha/Overview]] and [[Projects/Beta/Overview]]
    """
}

private func styleGuideNote() -> String {
    """
    # Style Guide

    ## Layout

    Use generous spacing, strong hierarchy, and deliberate typography.

    ## Motion

    - Fade between notes
    - Keep transitions calm
    """
}

private func readerPlaygroundNote() -> String {
    """
    ---
    aliases: [Reader Sandbox]
    status: active
    tags: [playground, reader]
    owner: Design Systems
    ---
    # Reader Playground

    Test inline links like [[Projects/Alpha/Overview]], attachment links such as [Reader Notes](Assets/Documents/reader-notes.txt), and tags like #playground.

    > [!tip] Playground
    > This note is designed to combine many reader features in one place.

    ## Embedded Media

    Here is an inline project image ![[Projects/Alpha/cover.png|Alpha board]].
    The manual also appears as an unsupported inline fallback block below.

    ![[Assets/Documents/operations-manual.pdf]]

    ## Comparison Table

    | View | Expectation |
    | --- | --- |
    | Sidebar | Folder grouping |
    | Reader | Rich markdown blocks |
    | Navigation | Anchor and note jumps |

    ## List Fidelity

    1. Validate ordered list markers
    2. Confirm nested list indentation
       - Capture a screenshot of the reader
       - Check spacing against the callout and table sections
    - [ ] Verify unfinished checklist styling
    - [x] Confirm completed checklist styling

    ## Footnotes And Fallbacks

    Reader polish should include graceful degradation for diagrams[^diagram].

    ```mermaid
    graph TD
      Reader --> Vault
      Vault --> Graph
    ```

    [^diagram]: Mermaid and other advanced blocks should stay visible even before full rendering exists.
    """
}

private func projectIndexNote(project: String, slug: String) -> String {
    """
    # \(project) Index

    This is the central map for #\(slug) work.

    - [[Overview]]
    - [[Daily]]
    - [[Roadmap]]
    """
}

private func projectDailyNote(project: String, slug: String) -> String {
    """
    # \(project) Daily

    Daily coordination for #\(slug).

    ## Updates

    - Reviewed [[Overview]]
    - Opened [Project Spec](spec.pdf)
    - Cross-checked [Architecture Patterns](Knowledge/Architecture/Index.md#Patterns)
    """
}

private func projectRoadmapNote(project: String, slug: String) -> String {
    """
    # \(project) Roadmap

    ## Now

    - Ship the \(project) readout
    - Keep #\(slug) quality high

    ## Later

    - Merge sprint learnings from [[Sprints/Sprint 01]]
    - Capture decisions in [[Notes/Decision 01]]
    """
}

private func projectOverviewNote(project: String, slug: String) -> String {
    """
    ---
    project: \(project)
    aliases:
      - \(project) Summary
      - \(project) Launch Brief
    status: active
    tags: [\(slug), launch]
    owner: \(project) Team
    ---
    # \(project) Overview

    The \(project) stream tracks #\(slug), #launch, and #reader-validation goals.

    > [!info] Snapshot
    > Use [[Daily]] for the local log, [[Index]] for the folder map, and [[Roadmap]] for the longer view.

    ## Overview

    Review [Architecture Patterns](Knowledge/Architecture/Index.md#Patterns), inspect the [Project Spec](spec.pdf), and keep the inline board ![[cover.png|\(project) board]] visible.

    ## Metrics

    | Metric | Value |
    | --- | --- |
    | Owner Count | 3 |
    | Review Depth | High |
    | Mode | Read only |

    ## Risks & Decisions

    - Keep folder-local assets resolving before shared ones
    - Test duplicate names like `Daily.md`
    """
}

private func sprintNote(project: String, slug: String, sprintIndex: Int) -> String {
    """
    # Sprint \(padded(sprintIndex))

    Sprint planning for \(project) and #\(slug).

    - Review [[Overview]]
    - Capture outcomes in [[Decision \(padded(((sprintIndex - 1) % 9) + 1))]]
    - Verify [Operations Manual](Assets/Documents/operations-manual.pdf)
    """
}

private func decisionNote(project: String, slug: String, decisionIndex: Int) -> String {
    """
    # Decision \(padded(decisionIndex))

    ## Context

    The \(project) team recorded a #decision for #\(slug) work.

    ## Rationale

    - Align with [[Overview]]
    - Keep navigation deterministic
    """
}

private func architectureIndexNote() -> String {
    """
    # Architecture Index

    ## Patterns

    - [[Pattern 01]]
    - [[Pattern 02]]
    - [[Pattern 03]]

    ## Operations

    See [Operations Manual](Assets/Documents/operations-manual.pdf) and [[Knowledge/Swift/Index]].
    """
}

private func architecturePatternNote(noteIndex: Int) -> String {
    """
    # Pattern \(padded(noteIndex))

    Pattern \(noteIndex) describes a navigation or indexing choice for #architecture.

    > [!warning] Constraint
    > Preserve read-only behavior while still rendering rich note content.
    """
}

private func swiftIndexNote() -> String {
    """
    # Swift Index

    - [[Technique 01]]
    - [[Technique 02]]
    - [[Technique 03]]
    """
}

private func swiftTechniqueNote(noteIndex: Int) -> String {
    """
    # Technique \(padded(noteIndex))

    Use Swift feature \(noteIndex) to keep the app testable, portable, and predictable.

    ## Notes

    - Works with #swift
    - Pairs with [[Knowledge/Architecture/Index]]
    """
}

private func journalNote(monthValue: String, dayValue: String, project: String) -> String {
    let slug = lowercase(project)
    return """
    # 2026-\(monthValue)-\(dayValue)

    Journal note for #journal and #\(slug).

    - Reviewed [[Projects/\(project)/Overview]]
    - Compared [[Projects/\(project)/Daily]]
    - Opened [Reader Notes](Assets/Documents/reader-notes.txt)
    """
}

private func weeklySyncNote(week: Int, project: String) -> String {
    """
    # Weekly Sync

    ## Agenda

    - Review [[Projects/\(project)/Overview]]
    - Update [[Projects/\(project)/Roadmap]]
    - Confirm [Architecture Patterns](Knowledge/Architecture/Index.md#Patterns)
    """
}

private func lowercase(_ value: String) -> String {
    value.lowercased()
}

private func padded(_ value: Int) -> String {
    String(format: "%02d", value)
}

private func makePNGData() -> Data {
    Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0msAAAAASUVORK5CYII="
    ) ?? Data()
}

private func makeBlankPDFData() -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 240, height: 120)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        return Data("%PDF-1.4\n%%EOF\n".utf8)
    }

    context.beginPDFPage(nil)
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(mediaBox)
    context.endPDFPage()
    context.closePDF()
    return data as Data
}
