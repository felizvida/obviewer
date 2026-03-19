import AppKit
import SwiftUI

struct ReaderView: View {
    let note: VaultNote
    let snapshot: VaultSnapshot
    let onNavigate: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header

                Divider()

                ForEach(Array(note.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }

                if note.outboundLinks.isEmpty == false {
                    linkedNotes
                }
            }
            .padding(56)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(note.title)
                .font(.system(size: 48, weight: .bold, design: .serif))
                .textSelection(.enabled)

            Text(note.relativePath)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                metricPill(systemImage: "clock", text: "\(note.readingTimeMinutes) min read")
                metricPill(systemImage: "text.word.spacing", text: "\(note.wordCount) words")

                ForEach(note.tags.prefix(4), id: \.self) { tag in
                    metricPill(systemImage: "tag", text: tag)
                }
            }
        }
    }

    private func metricPill(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
    }

    @ViewBuilder
    private func blockView(_ block: RenderBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(for: level))
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 8 : 12)

        case .paragraph(let text):
            Text(text)
                .font(.system(size: 21, weight: .regular, design: .serif))
                .lineSpacing(7)
                .foregroundStyle(Color.black.opacity(0.82))
                .textSelection(.enabled)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color.black.opacity(0.72))
                            .frame(width: 6, height: 6)
                            .padding(.top, 11)

                        Text(item)
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .lineSpacing(6)
                            .textSelection(.enabled)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 4)

                Text(text)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }
            .padding(.leading, 6)

        case .callout(let kind, let title, let body):
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: iconName(for: kind))
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(body)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(calloutColor(for: kind).opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(calloutColor(for: kind).opacity(0.25), lineWidth: 1)
            )

        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 12) {
                if let language {
                    Text(language.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal) {
                    Text(code)
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(red: 0.95, green: 0.95, blue: 0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.14, green: 0.15, blue: 0.16))
            )

        case .image(let path, let alt):
            if let attachment = snapshot.attachment(for: path), attachment.kind == .image {
                if let image = NSImage(contentsOf: attachment.url) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )

                        Text(alt ?? path)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label(path, systemImage: "photo")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private var linkedNotes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Linked Notes")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            FlowLayout(items: note.outboundLinks) { link in
                Button(link) {
                    onNavigate(link)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.72))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            }
        }
        .padding(.top, 12)
    }

    private func iconName(for kind: CalloutKind) -> String {
        switch kind {
        case .note:
            return "note.text"
        case .info:
            return "info.circle"
        case .tip:
            return "lightbulb"
        case .warning:
            return "exclamationmark.triangle"
        case .danger:
            return "flame"
        case .success:
            return "checkmark.seal"
        }
    }

    private func calloutColor(for kind: CalloutKind) -> Color {
        switch kind {
        case .note:
            return Color(red: 0.39, green: 0.49, blue: 0.60)
        case .info:
            return Color(red: 0.22, green: 0.49, blue: 0.77)
        case .tip:
            return Color(red: 0.46, green: 0.52, blue: 0.21)
        case .warning:
            return Color(red: 0.74, green: 0.50, blue: 0.18)
        case .danger:
            return Color(red: 0.73, green: 0.28, blue: 0.23)
        case .success:
            return Color(red: 0.18, green: 0.58, blue: 0.36)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 38, weight: .bold, design: .serif)
        case 2:
            return .system(size: 31, weight: .bold, design: .serif)
        case 3:
            return .system(size: 26, weight: .semibold, design: .serif)
        default:
            return .system(size: 22, weight: .semibold, design: .serif)
        }
    }
}

private struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(items, id: \.self) { item in
                        content(item)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
