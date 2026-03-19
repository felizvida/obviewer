import AppKit
import ObviewerCore
import SwiftUI

struct ReaderView: View {
    let note: VaultNote
    let snapshot: VaultSnapshot
    let onNavigate: (String, String?) -> Void
    let onSelectTag: (String) -> Void
    let pendingAnchorID: String?
    let onConsumePendingAnchor: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 30) {
                        header

                        Divider()

                        ForEach(Array(note.blocks.enumerated()), id: \.offset) { _, block in
                            blockView(block, proxy: proxy)
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)

                    ReaderOutlineRail(note: note) { anchor in
                        scroll(to: anchor, using: proxy)
                    } onNavigate: { target in
                        onNavigate(target, nil)
                    }
                }
                .padding(56)
                .frame(maxWidth: 1_260, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                handlePendingAnchor(using: proxy)
            }
            .onChange(of: pendingAnchorID) {
                handlePendingAnchor(using: proxy)
            }
        }
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
    private func blockView(_ block: RenderBlock, proxy: ScrollViewProxy) -> some View {
        switch block {
        case .heading(let level, let text, let anchor):
            RichTextView(
                text: text,
                size: headingSize(for: level),
                weight: headingWeight(for: level),
                design: .serif,
                onNavigate: onNavigate,
                onOpenAttachment: openAttachment(path:),
                onOpenAnchor: { scroll(to: $0, using: proxy) },
                onSelectTag: onSelectTag
            )
            .padding(.top, level == 1 ? 8 : 12)
            .id(anchor)

        case .paragraph(let text):
            RichTextView(
                text: text,
                size: 21,
                weight: .regular,
                design: .serif,
                color: Color.black.opacity(0.82),
                onNavigate: onNavigate,
                onOpenAttachment: openAttachment(path:),
                onOpenAnchor: { scroll(to: $0, using: proxy) },
                onSelectTag: onSelectTag
            )
            .lineSpacing(7)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color.black.opacity(0.72))
                            .frame(width: 6, height: 6)
                            .padding(.top, 11)

                        RichTextView(
                            text: item,
                            size: 20,
                            weight: .regular,
                            design: .serif,
                            onNavigate: onNavigate,
                            onOpenAttachment: openAttachment(path:),
                            onOpenAnchor: { scroll(to: $0, using: proxy) },
                            onSelectTag: onSelectTag
                        )
                        .lineSpacing(6)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 4)

                RichTextView(
                    text: text,
                    size: 20,
                    weight: .regular,
                    design: .serif,
                    color: .secondary,
                    onNavigate: onNavigate,
                    onOpenAttachment: openAttachment(path:),
                    onOpenAnchor: { scroll(to: $0, using: proxy) },
                    onSelectTag: onSelectTag
                )
                .lineSpacing(6)
            }
            .padding(.leading, 6)

        case .callout(let kind, let title, let body):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: iconName(for: kind))
                    RichTextView(
                        text: title,
                        size: 14,
                        weight: .bold,
                        design: .rounded,
                        onNavigate: onNavigate,
                        onOpenAttachment: openAttachment(path:),
                        onOpenAnchor: { scroll(to: $0, using: proxy) },
                        onSelectTag: onSelectTag
                    )
                }

                RichTextView(
                    text: body,
                    size: 18,
                    weight: .regular,
                    design: .serif,
                    onNavigate: onNavigate,
                    onOpenAttachment: openAttachment(path:),
                    onOpenAnchor: { scroll(to: $0, using: proxy) },
                    onSelectTag: onSelectTag
                )
                .lineSpacing(6)
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

        case .table(let headers, let rows):
            TableBlockView(
                headers: headers,
                rows: rows,
                onNavigate: onNavigate,
                onOpenAttachment: openAttachment(path:),
                onOpenAnchor: { scroll(to: $0, using: proxy) },
                onSelectTag: onSelectTag
            )

        case .image(let path, let alt):
            if let attachment = snapshot.attachment(for: path, from: note.id), attachment.kind == .image {
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

    private func openAttachment(path: String) {
        guard let attachment = snapshot.attachment(for: path, from: note.id) else {
            return
        }

        NSWorkspace.shared.open(attachment.url)
    }

    private func handlePendingAnchor(using proxy: ScrollViewProxy) {
        guard let pendingAnchorID, pendingAnchorID.isEmpty == false else {
            return
        }

        scroll(to: pendingAnchorID, using: proxy)
        onConsumePendingAnchor()
    }

    private func scroll(to anchor: String, using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.32)) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
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

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            return 38
        case 2:
            return 31
        case 3:
            return 26
        default:
            return 22
        }
    }

    private func headingWeight(for level: Int) -> Font.Weight {
        switch level {
        case 1, 2:
            return .bold
        default:
            return .semibold
        }
    }
}

private struct ReaderOutlineRail: View {
    let note: VaultNote
    let onScrollToSection: (String) -> Void
    let onNavigate: (String) -> Void

    var body: some View {
        if note.tableOfContents.isEmpty == false || note.outboundLinks.isEmpty == false {
            VStack(alignment: .leading, spacing: 18) {
                if note.tableOfContents.isEmpty == false {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Contents")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        ForEach(note.tableOfContents) { item in
                            Button {
                                onScrollToSection(item.id)
                            } label: {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, CGFloat(max(item.level - 1, 0)) * 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if note.outboundLinks.isEmpty == false {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Linked Notes")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        ForEach(note.outboundLinks, id: \.self) { link in
                            Button(link) {
                                onNavigate(link)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 260, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.48))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
        }
    }
}

private struct TableBlockView: View {
    let headers: [RichText]
    let rows: [[RichText]]
    let onNavigate: (String, String?) -> Void
    let onOpenAttachment: (String) -> Void
    let onOpenAnchor: (String) -> Void
    let onSelectTag: (String) -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    RichTextView(
                        text: header,
                        size: 13,
                        weight: .bold,
                        design: .rounded,
                        onNavigate: onNavigate,
                        onOpenAttachment: onOpenAttachment,
                        onOpenAnchor: onOpenAnchor,
                        onSelectTag: onSelectTag
                    )
                    .padding(.bottom, 6)
                }
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        RichTextView(
                            text: cell,
                            size: 16,
                            weight: .regular,
                            design: .serif,
                            onNavigate: onNavigate,
                            onOpenAttachment: onOpenAttachment,
                            onOpenAnchor: onOpenAnchor,
                            onSelectTag: onSelectTag
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.64))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}
