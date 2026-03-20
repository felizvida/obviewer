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
    @State private var presentedImage: PresentedAttachmentImage?

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
        .sheet(item: $presentedImage) { presentedImage in
            ImageLightboxView(presentedImage: presentedImage)
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
                onSelectTag: onSelectTag,
                inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
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
                onSelectTag: onSelectTag,
                inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
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
                            onSelectTag: onSelectTag,
                            inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                            onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
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
                    onSelectTag: onSelectTag,
                    inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                    onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
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
                        onSelectTag: onSelectTag,
                        inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                        onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
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
                    onSelectTag: onSelectTag,
                    inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                    onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
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
                onSelectTag: onSelectTag,
                inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
            )

        case .image(let path, let alt, let sizeHint):
            imageBlock(path: path, alt: alt, sizeHint: sizeHint)

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func imageBlock(path: String, alt: String?, sizeHint: ImageSizeHint?) -> some View {
        if let presentedImage = makePresentedImage(path: path, alt: alt, sizeHint: sizeHint) {
            Button {
                self.presentedImage = presentedImage
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: presentedImage.image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                maxWidth: resolvedImageWidth(
                                    sizeHint: presentedImage.sizeHint,
                                    imageSize: presentedImage.image.size
                                ),
                                maxHeight: resolvedImageHeight(
                                    sizeHint: presentedImage.sizeHint,
                                    imageSize: presentedImage.image.size
                                ),
                                alignment: .leading
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)

                        Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.88))
                            )
                            .padding(16)
                    }

                    HStack(spacing: 10) {
                        Text(presentedImage.caption)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        if let sizeSummary = imageSizeSummary(sizeHint: presentedImage.sizeHint) {
                            Text(sizeSummary)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.66))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.74))
                                )
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Unable to render image", systemImage: "photo.badge.exclamationmark")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(path)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.54))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func openAttachment(path: String) {
        guard let attachment = snapshot.attachment(for: path, from: note.id) else {
            return
        }

        if attachment.kind == .image, let presentedImage = makePresentedImage(path: path, alt: nil, sizeHint: nil) {
            self.presentedImage = presentedImage
            return
        }

        NSWorkspace.shared.open(attachment.url)
    }

    private func resolveInlineImage(
        path: String,
        alt: String?,
        sizeHint: ImageSizeHint?
    ) -> ResolvedInlineImage? {
        guard let presentedImage = makePresentedImage(path: path, alt: alt, sizeHint: sizeHint) else {
            return nil
        }

        return ResolvedInlineImage(
            path: presentedImage.attachment.relativePath,
            image: presentedImage.image,
            caption: presentedImage.caption,
            sizeHint: presentedImage.sizeHint
        )
    }

    private func presentInlineImage(
        path: String,
        alt: String?,
        sizeHint: ImageSizeHint?
    ) {
        guard let presentedImage = makePresentedImage(path: path, alt: alt, sizeHint: sizeHint) else {
            openAttachment(path: path)
            return
        }

        self.presentedImage = presentedImage
    }

    private func makePresentedImage(
        path: String,
        alt: String?,
        sizeHint: ImageSizeHint?
    ) -> PresentedAttachmentImage? {
        guard let attachment = snapshot.attachment(for: path, from: note.id), attachment.kind == .image else {
            return nil
        }
        guard let image = NSImage(contentsOf: attachment.url) else {
            return nil
        }

        let trimmedAlt = alt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let caption = trimmedAlt.isEmpty ? attachment.relativePath : trimmedAlt
        return PresentedAttachmentImage(
            id: note.id + "::" + attachment.relativePath,
            attachment: attachment,
            image: image,
            caption: caption,
            sizeHint: sizeHint
        )
    }

    private func resolvedImageWidth(sizeHint: ImageSizeHint?, imageSize: NSSize) -> CGFloat {
        if let width = sizeHint?.width {
            return min(CGFloat(width), 780)
        }

        let naturalWidth = imageSize.width > 0 ? imageSize.width : 680
        return min(max(naturalWidth, 260), 780)
    }

    private func resolvedImageHeight(sizeHint: ImageSizeHint?, imageSize: NSSize) -> CGFloat? {
        if let height = sizeHint?.height {
            return min(CGFloat(height), 640)
        }

        if imageSize.height > 0 {
            return min(max(imageSize.height, 180), 560)
        }

        return nil
    }

    private func imageSizeSummary(sizeHint: ImageSizeHint?) -> String? {
        guard let sizeHint, sizeHint.hasExplicitDimensions else {
            return nil
        }

        if let width = sizeHint.width, let height = sizeHint.height {
            return "\(Int(width)) x \(Int(height))"
        }
        if let width = sizeHint.width {
            return "\(Int(width)) wide"
        }
        if let height = sizeHint.height {
            return "\(Int(height)) tall"
        }
        return nil
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

private struct PresentedAttachmentImage: Identifiable {
    let id: String
    let attachment: VaultAttachment
    let image: NSImage
    let caption: String
    let sizeHint: ImageSizeHint?
}

private struct ImageLightboxView: View {
    let presentedImage: PresentedAttachmentImage
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentedImage.caption)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                    Text(presentedImage.attachment.relativePath)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 20)

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 12) {
                        Text("Zoom")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Slider(value: $zoom, in: 0.75 ... 4, step: 0.25)
                            .frame(width: 180)

                        Text("\(zoom.formatted(.number.precision(.fractionLength(2))))x")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 50, alignment: .trailing)
                    }

                    HStack(spacing: 10) {
                        Button("Open Original") {
                            NSWorkspace.shared.open(presentedImage.attachment.url)
                        }
                        .buttonStyle(.bordered)

                        Button("Reveal File") {
                            NSWorkspace.shared.activateFileViewerSelecting([presentedImage.attachment.url])
                        }
                        .buttonStyle(.bordered)

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.10, blue: 0.12),
                        Color(red: 0.13, green: 0.14, blue: 0.17),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: presentedImage.image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: baseWidth * zoom)
                        .padding(48)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }

    private var baseWidth: CGFloat {
        let naturalWidth = presentedImage.image.size.width > 0 ? presentedImage.image.size.width : 900
        return min(max(naturalWidth, 360), 1_280)
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
    let inlineImageResolver: (String, String?, ImageSizeHint?) -> ResolvedInlineImage?
    let onOpenInlineImage: (String, String?, ImageSizeHint?) -> Void

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
                        onSelectTag: onSelectTag,
                        inlineImageResolver: inlineImageResolver,
                        onOpenInlineImage: onOpenInlineImage
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
                            onSelectTag: onSelectTag,
                            inlineImageResolver: inlineImageResolver,
                            onOpenInlineImage: onOpenInlineImage
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
