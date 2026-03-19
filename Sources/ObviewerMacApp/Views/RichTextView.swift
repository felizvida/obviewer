import ObviewerCore
import SwiftUI

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

    var body: some View {
        Text(makeAttributedString())
            .environment(\.openURL, OpenURLAction { url in
                handle(url)
            })
            .textSelection(.enabled)
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
}
