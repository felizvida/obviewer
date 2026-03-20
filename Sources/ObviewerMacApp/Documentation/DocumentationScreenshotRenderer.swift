import AppKit
import ObviewerCore
import SwiftUI

public struct DocumentationScreenshotSpec: Sendable {
    public let fileName: String
    public let title: String
    public let selectedNoteID: String?
    public let searchText: String
    public let appSize: CGSize
    public let canvasSize: CGSize

    public init(
        fileName: String,
        title: String,
        selectedNoteID: String? = nil,
        searchText: String = "",
        appSize: CGSize = CGSize(width: 1_420, height: 900),
        canvasSize: CGSize = CGSize(width: 1_760, height: 1_140)
    ) {
        self.fileName = fileName
        self.title = title
        self.selectedNoteID = selectedNoteID
        self.searchText = searchText
        self.appSize = appSize
        self.canvasSize = canvasSize
    }
}

public enum DocumentationScreenshotRenderer {
    @MainActor
    public static func render(
        vaultURL: URL,
        specs: [DocumentationScreenshotSpec],
        outputDirectory: URL
    ) async throws {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        for spec in specs {
            let model = AppModel(
                bookmarkStore: DocumentationBookmarkStore(),
                picker: DocumentationVaultPicker(url: vaultURL),
                reader: VaultReader(),
                securityScopeManager: DocumentationSecurityScopeManager()
            )

            await model.chooseVault()
            model.searchText = spec.searchText
            if let selectedNoteID = spec.selectedNoteID {
                model.selectedNoteID = selectedNoteID
            }

            let contentView = ContentView(model: model)
                .frame(width: spec.appSize.width, height: spec.appSize.height)

            let appImage = try renderAppView(contentView, size: spec.appSize)
            let mockup = composeMockup(
                appImage: appImage,
                title: spec.title,
                canvasSize: spec.canvasSize,
                chromeHeight: 56
            )

            try writePNG(
                image: mockup,
                to: outputDirectory.appendingPathComponent(spec.fileName, isDirectory: false)
            )
        }
    }

    @MainActor
    private static func renderAppView<V: View>(_ view: V, size: CGSize) throws -> NSImage {
        let hostingView = NSHostingView(rootView: AnyView(view))
        hostingView.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = hostingView
        window.displayIfNeeded()

        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let bounds = hostingView.bounds
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw DocumentationScreenshotError.captureFailed
        }
        hostingView.cacheDisplay(in: bounds, to: bitmap)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    private static func composeMockup(
        appImage: NSImage,
        title: String,
        canvasSize: CGSize,
        chromeHeight: CGFloat
    ) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        drawBackground(in: canvasRect)

        let windowWidth = appImage.size.width
        let windowHeight = appImage.size.height + chromeHeight
        let windowRect = CGRect(
            x: (canvasSize.width - windowWidth) / 2,
            y: (canvasSize.height - windowHeight) / 2,
            width: windowWidth,
            height: windowHeight
        )
        let contentRect = CGRect(
            x: windowRect.minX,
            y: windowRect.minY,
            width: appImage.size.width,
            height: appImage.size.height
        )
        let titleBarRect = CGRect(
            x: windowRect.minX,
            y: windowRect.maxY - chromeHeight,
            width: windowRect.width,
            height: chromeHeight
        )

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 34
        shadow.shadowOffset = CGSize(width: 0, height: -18)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.set()

        let roundedWindow = NSBezierPath(
            roundedRect: windowRect,
            xRadius: 28,
            yRadius: 28
        )
        NSColor.white.withAlphaComponent(0.95).setFill()
        roundedWindow.fill()

        NSGraphicsContext.current?.saveGraphicsState()
        roundedWindow.addClip()

        NSColor(calibratedWhite: 1.0, alpha: 0.88).setFill()
        titleBarRect.fill()

        appImage.draw(in: contentRect)
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.06).setStroke()
        roundedWindow.lineWidth = 1
        roundedWindow.stroke()

        drawTrafficLights(in: titleBarRect)
        drawWindowTitle(title, in: titleBarRect)
        return image
    }

    private static func drawBackground(in rect: CGRect) {
        let gradient = NSGradient(
            colors: [
                NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.91, alpha: 1),
                NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.90, alpha: 1),
                NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.92, alpha: 1),
            ]
        )
        gradient?.draw(in: rect, angle: 315)

        let highlight = NSBezierPath(ovalIn: CGRect(x: rect.maxX - 480, y: rect.maxY - 330, width: 420, height: 260))
        NSColor.white.withAlphaComponent(0.14).setFill()
        highlight.fill()
    }

    private static func drawTrafficLights(in titleBarRect: CGRect) {
        let colors = [
            NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.17, green: 0.80, blue: 0.36, alpha: 1),
        ]

        for (index, color) in colors.enumerated() {
            let circleRect = CGRect(
                x: titleBarRect.minX + 18 + CGFloat(index) * 16,
                y: titleBarRect.midY - 5,
                width: 10,
                height: 10
            )
            let circle = NSBezierPath(ovalIn: circleRect)
            color.setFill()
            circle.fill()
        }
    }

    private static func drawWindowTitle(_ title: String, in titleBarRect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.17, alpha: 0.82),
        ]
        let attributed = NSAttributedString(string: title, attributes: attributes)
        let size = attributed.size()
        let point = CGPoint(
            x: titleBarRect.midX - size.width / 2,
            y: titleBarRect.midY - size.height / 2
        )
        attributed.draw(at: point)
    }

    private static func writePNG(image: NSImage, to url: URL) throws {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw DocumentationScreenshotError.encodingFailed
        }
        try png.write(to: url)
    }
}

public enum DocumentationScreenshotError: LocalizedError {
    case captureFailed
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "Unable to capture the SwiftUI view into an image."
        case .encodingFailed:
            return "Unable to encode the screenshot as PNG."
        }
    }
}

@MainActor
private struct DocumentationBookmarkStore: VaultBookmarkStoring {
    func save(url: URL) throws {}
    func restore() throws -> URL? { nil }
}

@MainActor
private struct DocumentationVaultPicker: VaultChoosing {
    let url: URL?

    func chooseVault() -> URL? {
        url
    }
}

@MainActor
private final class DocumentationSecurityScopeManager: SecurityScopeManaging {
    func activate(url: URL) {}
}
