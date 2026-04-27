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
    @AppStorage("obviewer.reader.textScale") private var readerTextScale = 1.0
    @AppStorage("obviewer.reader.lineWidth") private var readerLineWidth = 860.0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    ReaderExperienceBar(
                        textScale: $readerTextScale,
                        lineWidth: $readerLineWidth
                    )
                    .frame(maxWidth: 1_180, alignment: .trailing)

                    HStack(alignment: .top, spacing: 30) {
                        VStack(alignment: .leading, spacing: 30) {
                            header

                            ReaderSectionDivider()

                            ForEach(Array(note.blocks.enumerated()), id: \.offset) { _, block in
                                blockView(block, proxy: proxy)
                            }
                        }
                        .frame(maxWidth: contentWidth, alignment: .leading)
                        .padding(42)
                        .background(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(VisualTheme.readerSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(Color.white.opacity(0.72), lineWidth: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(Color.black.opacity(0.045), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 24, x: 0, y: 14)

                        ReaderOutlineRail(note: note) { anchor in
                            scroll(to: anchor, using: proxy)
                        } onNavigate: { target in
                            onNavigate(target, nil)
                        }
                    }
                }
                .padding(42)
                .frame(maxWidth: 1_340, alignment: .center)
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

    private var clampedTextScale: CGFloat {
        CGFloat(min(max(readerTextScale, 0.9), 1.25))
    }

    private var contentWidth: CGFloat {
        CGFloat(min(max(readerLineWidth, 680), 980))
    }

    private func scaled(_ size: CGFloat) -> CGFloat {
        (size * clampedTextScale).rounded()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [VisualTheme.fern, VisualTheme.ember.opacity(0.78)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 86, height: 5)

            Text(note.title)
                .font(.system(size: scaled(48), weight: .bold, design: .serif))
                .foregroundStyle(VisualTheme.ink)
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

            if note.frontmatter.isEmpty == false {
                FrontmatterSummaryCard(frontmatter: note.frontmatter)
            }
        }
    }

    private func metricPill(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .softPanel(cornerRadius: 999, opacity: 0.66)
    }

    @ViewBuilder
    private func blockView(_ block: RenderBlock, proxy: ScrollViewProxy) -> some View {
        switch block {
        case .heading(let level, let text, let anchor):
            RichTextView(
                text: text,
                size: scaled(headingSize(for: level)),
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
                size: scaled(21),
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
            .lineSpacing(scaled(7))

        case .list(let items):
            ListBlockView(
                items: items,
                textScale: clampedTextScale,
                onNavigate: onNavigate,
                onOpenAttachment: openAttachment(path:),
                onOpenAnchor: { scroll(to: $0, using: proxy) },
                onSelectTag: onSelectTag,
                inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
            )

        case .quote(let text):
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.black.opacity(0.14))
                    .frame(width: 4)

                RichTextView(
                    text: text,
                    size: scaled(20),
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
                .lineSpacing(scaled(6))
            }
            .padding(.leading, 6)

        case .callout(let kind, let title, let body):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: iconName(for: kind))
                    RichTextView(
                        text: title,
                        size: scaled(14),
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
                    size: scaled(18),
                    weight: .regular,
                    design: .serif,
                    onNavigate: onNavigate,
                    onOpenAttachment: openAttachment(path:),
                    onOpenAnchor: { scroll(to: $0, using: proxy) },
                    onSelectTag: onSelectTag,
                    inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                    onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
                )
                .lineSpacing(scaled(6))
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
            CodeBlockView(language: language, code: code, textScale: clampedTextScale)

        case .table(let headers, let rows):
            TableBlockView(
                headers: headers,
                rows: rows,
                textScale: clampedTextScale,
                onNavigate: onNavigate,
                onOpenAttachment: openAttachment(path:),
                onOpenAnchor: { scroll(to: $0, using: proxy) },
                onSelectTag: onSelectTag,
                inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
            )

        case .image(let path, let alt, let sizeHint):
            imageBlock(path: path, alt: alt, sizeHint: sizeHint)

        case .unsupported(let block):
            UnsupportedBlockView(
                block: block,
                onOpenAttachment: openAttachment(path:)
            )

        case .footnotes(let items):
            FootnotesBlockView(
                items: items,
                textScale: clampedTextScale,
                onNavigate: onNavigate,
                onOpenAttachment: openAttachment(path:),
                onOpenAnchor: { scroll(to: $0, using: proxy) },
                onSelectTag: onSelectTag,
                inlineImageResolver: resolveInlineImage(path:alt:sizeHint:),
                onOpenInlineImage: presentInlineImage(path:alt:sizeHint:)
            )

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

private struct ReaderSectionDivider: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.09),
                Color.black.opacity(0.02),
                .clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.vertical, 2)
    }
}

private struct ReaderExperienceBar: View {
    @Binding var textScale: Double
    @Binding var lineWidth: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(VisualTheme.fern)

            controlButton(systemImage: "textformat.size.smaller", help: "Smaller text") {
                adjustTextScale(by: -0.05)
            }

            controlButton(systemImage: "textformat.size.larger", help: "Larger text") {
                adjustTextScale(by: 0.05)
            }

            Divider()
                .frame(height: 16)

            controlButton(systemImage: "arrow.down.right.and.arrow.up.left", help: "Narrower page") {
                adjustLineWidth(by: -40)
            }

            controlButton(systemImage: "arrow.up.left.and.arrow.down.right", help: "Wider page") {
                adjustLineWidth(by: 40)
            }

            controlButton(systemImage: "arrow.counterclockwise", help: "Reset reading layout") {
                reset()
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .softPanel(cornerRadius: 999, opacity: 0.56)
    }

    private func controlButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VisualTheme.softInk)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func adjustTextScale(by delta: Double) {
        withAnimation(.easeInOut(duration: 0.18)) {
            textScale = min(max(textScale + delta, 0.9), 1.25)
        }
    }

    private func adjustLineWidth(by delta: Double) {
        withAnimation(.easeInOut(duration: 0.18)) {
            lineWidth = min(max(lineWidth + delta, 680), 980)
        }
    }

    private func reset() {
        withAnimation(.easeInOut(duration: 0.18)) {
            textScale = 1
            lineWidth = 860
        }
    }
}

private struct FrontmatterSummaryCard: View {
    let frontmatter: NoteFrontmatter

    private let columns = [
        GridItem(.flexible(minimum: 180), spacing: 14, alignment: .topLeading),
        GridItem(.flexible(minimum: 180), spacing: 14, alignment: .topLeading),
    ]

    private var displayEntries: [FrontmatterEntry] {
        frontmatter.displayEntries(limit: 6)
    }

    var body: some View {
        if displayEntries.isEmpty == false {
            VStack(alignment: .leading, spacing: 14) {
                Text("Metadata")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(displayEntries, id: \.key) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.key.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.46))

                            Text(entry.value.displayText)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.78))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.62))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}

private struct ListBlockView: View {
    let items: [RenderListItem]
    let textScale: CGFloat
    let onNavigate: (String, String?) -> Void
    let onOpenAttachment: (String) -> Void
    let onOpenAnchor: (String) -> Void
    let onSelectTag: (String) -> Void
    let inlineImageResolver: (String, String?, ImageSizeHint?) -> ResolvedInlineImage?
    let onOpenInlineImage: (String, String?, ImageSizeHint?) -> Void

    var body: some View {
        ListItemsGroupView(
            items: items,
            level: 0,
            textScale: textScale,
            onNavigate: onNavigate,
            onOpenAttachment: onOpenAttachment,
            onOpenAnchor: onOpenAnchor,
            onSelectTag: onSelectTag,
            inlineImageResolver: inlineImageResolver,
            onOpenInlineImage: onOpenInlineImage
        )
    }
}

private struct ListItemsGroupView: View {
    let items: [RenderListItem]
    let level: Int
    let textScale: CGFloat
    let onNavigate: (String, String?) -> Void
    let onOpenAttachment: (String) -> Void
    let onOpenAnchor: (String) -> Void
    let onSelectTag: (String) -> Void
    let inlineImageResolver: (String, String?, ImageSizeHint?) -> ResolvedInlineImage?
    let onOpenInlineImage: (String, String?, ImageSizeHint?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        markerView(for: item.marker)
                            .frame(width: 28, alignment: .trailing)
                            .padding(.top, markerTopPadding(for: item.marker))

                        RichTextView(
                            text: item.text,
                            size: scaled(20),
                            weight: .regular,
                            design: .serif,
                            onNavigate: onNavigate,
                            onOpenAttachment: onOpenAttachment,
                            onOpenAnchor: onOpenAnchor,
                            onSelectTag: onSelectTag,
                            inlineImageResolver: inlineImageResolver,
                            onOpenInlineImage: onOpenInlineImage
                        )
                        .lineSpacing(scaled(6))
                    }

                    if item.children.isEmpty == false {
                        ListItemsGroupView(
                            items: item.children,
                            level: level + 1,
                            textScale: textScale,
                            onNavigate: onNavigate,
                            onOpenAttachment: onOpenAttachment,
                            onOpenAnchor: onOpenAnchor,
                            onSelectTag: onSelectTag,
                            inlineImageResolver: inlineImageResolver,
                            onOpenInlineImage: onOpenInlineImage
                        )
                        .padding(.leading, 30)
                    }
                }
            }
        }
        .padding(.leading, CGFloat(level) * 6)
    }

    @ViewBuilder
    private func markerView(for marker: RenderListMarker) -> some View {
        switch marker {
        case .unordered:
            Circle()
                .fill(Color.black.opacity(0.72))
                .frame(width: 6, height: 6)
        case .ordered(let number):
            Text("\(number).")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.72))
        case .task(let isCompleted):
            Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    isCompleted
                        ? Color(red: 0.21, green: 0.58, blue: 0.37)
                        : Color.black.opacity(0.55)
                )
        }
    }

    private func markerTopPadding(for marker: RenderListMarker) -> CGFloat {
        switch marker {
        case .unordered:
            return 11
        case .ordered:
            return 4
        case .task:
            return 5
        }
    }

    private func scaled(_ size: CGFloat) -> CGFloat {
        (size * textScale).rounded()
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String
    let textScale: CGFloat
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(languageLabel, systemImage: "curlybraces")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))

                Spacer(minLength: 16)

                Button {
                    copyCode()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.white.opacity(0.82))
            }

            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: scaled(15), weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(red: 0.95, green: 0.95, blue: 0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.14, blue: 0.15),
                            Color(red: 0.17, green: 0.19, blue: 0.18),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
    }

    private var languageLabel: String {
        guard let language, language.isEmpty == false else {
            return "CODE"
        }
        return language.uppercased()
    }

    private func scaled(_ size: CGFloat) -> CGFloat {
        (size * textScale).rounded()
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation(.easeInOut(duration: 0.14)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeInOut(duration: 0.14)) {
                copied = false
            }
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
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(VisualTheme.selectedSurface)

                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(VisualTheme.fern)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(presentedImage.caption)
                            .font(.system(size: 24, weight: .bold, design: .serif))
                        Text(presentedImage.attachment.relativePath)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 20)

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            adjustZoom(by: -0.25)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .help("Zoom out")

                        Slider(value: $zoom, in: 0.75 ... 4, step: 0.25)
                            .frame(width: 180)

                        Button {
                            adjustZoom(by: 0.25)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .help("Zoom in")

                        Text("\(zoom.formatted(.number.precision(.fractionLength(2))))x")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .buttonStyle(.borderless)

                    HStack(spacing: 10) {
                        Button {
                            resetZoom()
                        } label: {
                            Label("Fit", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            NSWorkspace.shared.open(presentedImage.attachment.url)
                        } label: {
                            Label("Open Original", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([presentedImage.attachment.url])
                        } label: {
                            Label("Reveal File", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .background(VisualTheme.readerSurface)

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

                LightboxGrid()
                    .opacity(0.2)

                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: presentedImage.image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: baseWidth * zoom)
                        .padding(48)
                        .shadow(color: Color.black.opacity(0.28), radius: 22, x: 0, y: 14)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }

    private var baseWidth: CGFloat {
        let naturalWidth = presentedImage.image.size.width > 0 ? presentedImage.image.size.width : 900
        return min(max(naturalWidth, 360), 1_280)
    }

    private func adjustZoom(by delta: Double) {
        withAnimation(.easeInOut(duration: 0.16)) {
            zoom = min(max(zoom + delta, 0.75), 4)
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.16)) {
            zoom = 1
        }
    }
}

private struct LightboxGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 38
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(Color.white.opacity(0.18)), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}

private struct ReaderOutlineRail: View {
    let note: VaultNote
    let onScrollToSection: (String) -> Void
    let onNavigate: (String) -> Void
    @State private var hoveredSectionID: String?
    @State private var hoveredLink: String?

    var body: some View {
        if note.tableOfContents.isEmpty == false || note.outboundLinks.isEmpty == false {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "sidebar.trailing")
                        .foregroundStyle(VisualTheme.fern)

                    Text("Navigation")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(VisualTheme.softInk)

                    Spacer(minLength: 4)
                }

                if note.tableOfContents.isEmpty == false {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Contents")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        ForEach(note.tableOfContents) { item in
                            Button {
                                onScrollToSection(item.id)
                            } label: {
                                RailSectionRow(
                                    title: item.title,
                                    level: item.level,
                                    isHovered: hoveredSectionID == item.id
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredSectionID = hovering ? item.id : nil
                            }
                        }
                    }
                }

                if note.outboundLinks.isEmpty == false {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Linked Notes")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        ForEach(note.outboundLinks, id: \.self) { link in
                            Button {
                                onNavigate(link)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.forward")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(VisualTheme.blue)

                                    Text(link)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .lineLimit(1)

                                    Spacer(minLength: 4)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white.opacity(hoveredLink == link ? 0.9 : 0.72))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredLink = hovering ? link : nil
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 260, alignment: .topLeading)
            .softPanel(cornerRadius: 24, opacity: 0.48)
        }
    }
}

private struct RailSectionRow: View {
    let title: String
    let level: Int
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(VisualTheme.fern.opacity(isHovered ? 0.78 : 0.34))
                .frame(width: 3, height: 18)

            Text(title)
                .font(.system(size: 13, weight: isHovered ? .bold : .medium, design: .rounded))
                .foregroundStyle(isHovered ? VisualTheme.ink : Color.primary)
                .lineLimit(2)

            Spacer(minLength: 4)
        }
        .padding(.leading, CGFloat(max(level - 1, 0)) * 12)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.78 : 0))
        )
        .animation(.easeInOut(duration: 0.14), value: isHovered)
    }
}

private struct TableBlockView: View {
    let headers: [RichText]
    let rows: [[RichText]]
    let textScale: CGFloat
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
                        size: scaled(13),
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
                            size: scaled(16),
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

    private func scaled(_ size: CGFloat) -> CGFloat {
        (size * textScale).rounded()
    }
}

private struct UnsupportedBlockView: View {
    let block: UnsupportedBlock
    let onOpenAttachment: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(block.title, systemImage: "sparkles.rectangle.stack")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.76))

            Text(block.body)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let attachmentPath = block.attachmentPath {
                Button {
                    onOpenAttachment(attachmentPath)
                } label: {
                    Label("Open Attachment", systemImage: "paperclip")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.96, green: 0.92, blue: 0.82).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(red: 0.55, green: 0.43, blue: 0.19).opacity(0.18), lineWidth: 1)
        )
    }
}

private struct FootnotesBlockView: View {
    let items: [FootnoteItem]
    let textScale: CGFloat
    let onNavigate: (String, String?) -> Void
    let onOpenAttachment: (String) -> Void
    let onOpenAnchor: (String) -> Void
    let onSelectTag: (String) -> Void
    let inlineImageResolver: (String, String?, ImageSizeHint?) -> ResolvedInlineImage?
    let onOpenInlineImage: (String, String?, ImageSizeHint?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Footnotes")
                .font(.system(size: scaled(22), weight: .bold, design: .serif))

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 14) {
                    Text("[\(item.label)]")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                        .padding(.top, 5)

                    RichTextView(
                        text: item.text,
                        size: scaled(17),
                        weight: .regular,
                        design: .serif,
                        color: Color.black.opacity(0.78),
                        onNavigate: onNavigate,
                        onOpenAttachment: onOpenAttachment,
                        onOpenAnchor: onOpenAnchor,
                        onSelectTag: onSelectTag,
                        inlineImageResolver: inlineImageResolver,
                        onOpenInlineImage: onOpenInlineImage
                    )
                    .id(item.id)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func scaled(_ size: CGFloat) -> CGFloat {
        (size * textScale).rounded()
    }
}
