import AppKit
import ObviewerCore
import SwiftUI

struct ResolvedInlineImage {
    let path: String
    let image: NSImage
    let caption: String
    let sizeHint: ImageSizeHint?
}

struct RichTextView: View {
    let text: RichText
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    var color: Color = .primary
    var onNavigate: (String, String?) -> Void = { _, _ in }
    var onOpenAttachment: (String) -> Void = { _ in }
    var onOpenAnchor: (String) -> Void = { _ in }
    var onSelectTag: (String) -> Void = { _ in }
    var inlineImageResolver: (String, String?, ImageSizeHint?) -> ResolvedInlineImage? = { _, _, _ in nil }
    var onOpenInlineImage: (String, String?, ImageSizeHint?) -> Void = { _, _, _ in }

    var body: some View {
        Group {
            if containsInlineImages {
                InlineRichFlowView(
                    tokens: makeFlowTokens(),
                    size: size,
                    weight: weight,
                    design: design,
                    color: color,
                    inlineImageResolver: inlineImageResolver,
                    onNavigate: onNavigate,
                    onOpenAttachment: onOpenAttachment,
                    onOpenAnchor: onOpenAnchor,
                    onSelectTag: onSelectTag,
                    onOpenInlineImage: onOpenInlineImage
                )
            } else {
                Text(makeAttributedString())
                    .environment(\.openURL, OpenURLAction { url in
                        handle(url)
                    })
                    .textSelection(.enabled)
            }
        }
    }

    private var containsInlineImages: Bool {
        text.runs.contains { run in
            if case .image = run {
                return true
            }
            return false
        }
    }

    private func makeAttributedString() -> AttributedString {
        var output = AttributedString()

        for run in text.runs {
            var segment = AttributedString(run.plainText)
            segment.font = .system(size: size, weight: weight, design: design)
            segment.foregroundColor = color

            switch run {
            case .text:
                break

            case .strong(let value):
                segment = AttributedString(value)
                segment.font = .system(size: size, weight: .bold, design: design)
                segment.foregroundColor = color

            case .emphasis(let value):
                segment = AttributedString(value)
                segment.font = .system(size: size, weight: weight, design: design).italic()
                segment.foregroundColor = color

            case .code(let value):
                segment = AttributedString(value)
                segment.font = .system(size: max(size - 3, 13), weight: .regular, design: .monospaced)
                segment.foregroundColor = Color(red: 0.84, green: 0.50, blue: 0.25)

            case .link(let label, let destination):
                segment = AttributedString(label)
                segment.font = .system(size: size, weight: .medium, design: design)
                segment.foregroundColor = Color(red: 0.15, green: 0.38, blue: 0.72)
                segment.link = makeURL(for: destination)

            case .image:
                break

            case .tag(let value):
                segment = AttributedString("#\(value)")
                segment.font = .system(size: size, weight: .semibold, design: design)
                segment.foregroundColor = Color(red: 0.20, green: 0.48, blue: 0.34)
                segment.link = makeTagURL(for: value)
            }

            output += segment
        }

        return output
    }

    private func makeURL(for destination: LinkDestination) -> URL? {
        switch destination {
        case .external(let value):
            return URL(string: value)
        case .note(let target, let anchor):
            var components = URLComponents()
            components.scheme = "obviewer-note"
            components.host = "note"
            let encodedTarget = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            components.percentEncodedPath = "/\(encodedTarget)"
            if let anchor, anchor.isEmpty == false {
                components.queryItems = [URLQueryItem(name: "anchor", value: anchor)]
            }
            return components.url
        case .anchor(let value):
            var components = URLComponents()
            components.scheme = "obviewer-anchor"
            components.host = "section"
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
            components.percentEncodedPath = "/\(encoded)"
            return components.url
        case .attachment(let value):
            var components = URLComponents()
            components.scheme = "obviewer-attachment"
            components.host = "file"
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
            components.percentEncodedPath = "/\(encoded)"
            return components.url
        }
    }

    private func makeTagURL(for tag: String) -> URL? {
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        return URL(string: "obviewer-tag://tag/\(encoded)")
    }

    private func handle(_ url: URL) -> OpenURLAction.Result {
        switch url.scheme {
        case "obviewer-note":
            let target = decodeURLPath(url)
            let anchor = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "anchor" })?
                .value
            if target.isEmpty == false {
                onNavigate(target, anchor)
            }
            return .handled

        case "obviewer-anchor":
            let anchor = decodeURLPath(url)
            if anchor.isEmpty == false {
                onOpenAnchor(anchor)
            }
            return .handled

        case "obviewer-attachment":
            let path = decodeURLPath(url)
            if path.isEmpty == false {
                onOpenAttachment(path)
            }
            return .handled

        case "obviewer-tag":
            let tag = decodeURLPath(url)
            if tag.isEmpty == false {
                onSelectTag(tag)
            }
            return .handled

        default:
            return .systemAction
        }
    }

    private func decodeURLPath(_ url: URL) -> String {
        String(url.path.dropFirst()).removingPercentEncoding ?? String(url.path.dropFirst())
    }

    private func makeFlowTokens() -> [InlineFlowToken] {
        InlineFlowTokenBuilder.tokens(from: text)
    }
}

private enum InlineTextTokenStyle {
    case plain
    case strong
    case emphasis
    case code
    case link(LinkDestination)
}

enum InlineFlowToken: Equatable {
    case plain(String)
    case strong(String)
    case emphasis(String)
    case code(String)
    case link(String, LinkDestination)
    case tag(String, String)
    case image(path: String, alt: String?, sizeHint: ImageSizeHint?)
}

enum InlineFlowTokenBuilder {
    static func tokens(from text: RichText) -> [InlineFlowToken] {
        var tokens = [InlineFlowToken]()

        for run in text.runs {
            switch run {
            case .text(let value):
                tokens.append(contentsOf: makeTextTokens(
                    for: value,
                    style: .plain,
                    preserveLeadingWhitespace: tokens.isEmpty == false
                ))
            case .strong(let value):
                tokens.append(contentsOf: makeTextTokens(
                    for: value,
                    style: .strong,
                    preserveLeadingWhitespace: tokens.isEmpty == false
                ))
            case .emphasis(let value):
                tokens.append(contentsOf: makeTextTokens(
                    for: value,
                    style: .emphasis,
                    preserveLeadingWhitespace: tokens.isEmpty == false
                ))
            case .code(let value):
                tokens.append(contentsOf: makeTextTokens(
                    for: value,
                    style: .code,
                    preserveLeadingWhitespace: tokens.isEmpty == false
                ))
            case .link(let label, let destination):
                tokens.append(contentsOf: makeTextTokens(
                    for: label,
                    style: .link(destination),
                    preserveLeadingWhitespace: tokens.isEmpty == false
                ))
            case .image(let path, let alt, let sizeHint):
                tokens.append(.image(path: path, alt: alt, sizeHint: sizeHint))
            case .tag(let value):
                tokens.append(.tag("#\(value)", value))
            }
        }

        return tokens
    }

    private static func makeTextTokens(
        for value: String,
        style: InlineTextTokenStyle,
        preserveLeadingWhitespace: Bool
    ) -> [InlineFlowToken] {
        let pieces = splitIntoFlowTextPieces(value, preserveLeadingWhitespace: preserveLeadingWhitespace)
        return pieces.map { piece in
            switch style {
            case .plain:
                return .plain(piece)
            case .strong:
                return .strong(piece)
            case .emphasis:
                return .emphasis(piece)
            case .code:
                return .code(piece)
            case .link(let destination):
                return .link(piece, destination)
            }
        }
    }

    private static func splitIntoFlowTextPieces(
        _ value: String,
        preserveLeadingWhitespace: Bool
    ) -> [String] {
        guard value.isEmpty == false else { return [] }

        var groups = [String]()
        var current = String(value[value.startIndex])
        var currentIsWhitespace = value[value.startIndex].isWhitespace

        for character in value.dropFirst() {
            if character.isWhitespace == currentIsWhitespace {
                current.append(character)
            } else {
                groups.append(current)
                current = String(character)
                currentIsWhitespace = character.isWhitespace
            }
        }
        groups.append(current)

        var pieces = [String]()
        var pendingPrefix = ""

        for group in groups {
            if group.allSatisfy(\.isWhitespace) {
                if pieces.isEmpty && preserveLeadingWhitespace == false {
                    continue
                }
                pendingPrefix += group
            } else {
                pieces.append(pendingPrefix + group)
                pendingPrefix.removeAll(keepingCapacity: true)
            }
        }

        if pendingPrefix.isEmpty == false {
            if let last = pieces.indices.last {
                pieces[last].append(pendingPrefix)
            } else if preserveLeadingWhitespace {
                pieces.append(pendingPrefix)
            }
        }

        return pieces.filter { $0.isEmpty == false }
    }
}

private struct InlineRichFlowView: View {
    let tokens: [InlineFlowToken]
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let color: Color
    let inlineImageResolver: (String, String?, ImageSizeHint?) -> ResolvedInlineImage?
    let onNavigate: (String, String?) -> Void
    let onOpenAttachment: (String) -> Void
    let onOpenAnchor: (String) -> Void
    let onSelectTag: (String) -> Void
    let onOpenInlineImage: (String, String?, ImageSizeHint?) -> Void

    var body: some View {
        InlineFlowLayout(itemSpacing: 0, rowSpacing: max(size * 0.22, 4)) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                tokenView(token)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tokenView(_ token: InlineFlowToken) -> some View {
        switch token {
        case .plain(let value):
            styledText(value)

        case .strong(let value):
            styledText(value, weight: .bold)

        case .emphasis(let value):
            styledText(value).italic()

        case .code(let value):
            Text(verbatim: value)
                .font(.system(size: max(size - 3, 13), weight: .regular, design: .monospaced))
                .foregroundStyle(Color(red: 0.84, green: 0.50, blue: 0.25))

        case .link(let label, let destination):
            Button {
                trigger(destination)
            } label: {
                Text(verbatim: label)
                    .font(.system(size: size, weight: .medium, design: design))
                    .foregroundStyle(Color(red: 0.15, green: 0.38, blue: 0.72))
            }
            .buttonStyle(.plain)

        case .tag(let label, let tagValue):
            Button {
                onSelectTag(tagValue)
            } label: {
                Text(verbatim: label)
                    .font(.system(size: size, weight: .semibold, design: design))
                    .foregroundStyle(Color(red: 0.20, green: 0.48, blue: 0.34))
            }
            .buttonStyle(.plain)

        case .image(let path, let alt, let sizeHint):
            if let resolvedImage = inlineImageResolver(path, alt, sizeHint) {
                Button {
                    onOpenInlineImage(path, alt, sizeHint)
                } label: {
                    inlineImageView(resolvedImage)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    onOpenAttachment(path)
                } label: {
                    Label(alt ?? path, systemImage: "photo")
                        .font(.system(size: max(size - 3, 13), weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func styledText(_ value: String, weight: Font.Weight? = nil) -> some View {
        Text(verbatim: value)
            .font(.system(size: size, weight: weight ?? self.weight, design: design))
            .foregroundStyle(color)
    }

    private func inlineImageView(_ resolvedImage: ResolvedInlineImage) -> some View {
        Image(nsImage: resolvedImage.image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(
                maxWidth: inlineImageWidth(sizeHint: resolvedImage.sizeHint, imageSize: resolvedImage.image.size),
                maxHeight: inlineImageHeight(sizeHint: resolvedImage.sizeHint, imageSize: resolvedImage.image.size)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
            .padding(.vertical, 4)
    }

    private func inlineImageWidth(sizeHint: ImageSizeHint?, imageSize: NSSize) -> CGFloat {
        if let width = sizeHint?.width {
            return min(max(CGFloat(width), 72), 360)
        }

        let naturalWidth = imageSize.width > 0 ? imageSize.width : 200
        return min(max(naturalWidth * 0.42, 96), 280)
    }

    private func inlineImageHeight(sizeHint: ImageSizeHint?, imageSize: NSSize) -> CGFloat {
        if let height = sizeHint?.height {
            return min(max(CGFloat(height), 56), 220)
        }

        let naturalHeight = imageSize.height > 0 ? imageSize.height : 120
        return min(max(naturalHeight * 0.42, 56), 220)
    }

    private func trigger(_ destination: LinkDestination) {
        switch destination {
        case .note(let target, let anchor):
            onNavigate(target, anchor)
        case .anchor(let anchor):
            onOpenAnchor(anchor)
        case .attachment(let path):
            onOpenAttachment(path)
        case .external(let value):
            if let url = URL(string: value) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private struct InlineFlowLayout: Layout {
    let itemSpacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layoutFrames(for: subviews, in: proposal).containerSize
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layoutFrames(for: subviews, in: proposal)
        for (index, frame) in result.frames.enumerated() {
            guard index < subviews.count else { continue }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func layoutFrames(
        for subviews: Subviews,
        in proposal: ProposedViewSize
    ) -> (frames: [CGRect], containerSize: CGSize) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var frames = [CGRect]()
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let measured = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let needsWrap = currentX > 0 && currentX + measured.width > maxWidth

            if needsWrap {
                currentY += rowHeight + rowSpacing
                currentX = 0
                rowHeight = 0
            }

            let frame = CGRect(origin: CGPoint(x: currentX, y: currentY), size: measured)
            frames.append(frame)

            currentX += measured.width + itemSpacing
            rowHeight = max(rowHeight, measured.height)
            usedWidth = max(usedWidth, frame.maxX)
        }

        let totalHeight = frames.isEmpty ? 0 : currentY + rowHeight
        let containerWidth = proposal.width ?? usedWidth
        return (frames, CGSize(width: containerWidth, height: totalHeight))
    }
}
