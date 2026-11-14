import ObviewerCore
import SwiftUI

struct GraphWorkspaceView: View {
    let snapshot: VaultSnapshot
    let subgraph: NoteGraphSubgraph?
    let selectedNoteID: String?
    let selectedNode: NoteGraphNode?
    let graphScope: GraphScope
    let searchText: String
    let onChangeScope: (GraphScope) -> Void
    let onSelectNote: (String) -> Void
    let onOpenReader: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let subgraph, subgraph.nodes.isEmpty == false {
                    GraphCanvasPanel(
                        snapshot: snapshot,
                        subgraph: subgraph,
                        graphScope: graphScope,
                        selectedNoteID: selectedNoteID,
                        onSelectNote: onSelectNote
                    )
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GraphInspectorPanel(
                snapshot: snapshot,
                selectedNode: selectedNode,
                graphScope: graphScope,
                searchText: searchText,
                onSelectNote: onSelectNote,
                onOpenReader: onOpenReader
            )
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// One sentence about what the graph shows, a quiet count, the folder colours,
    /// and a single toggle: the graph is local to the selected note unless
    /// "Whole Vault" is on.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(headerSubtitle)
                    .font(.system(size: 15, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Toggle(isOn: Binding(
                    get: { graphScope == .global },
                    set: { onChangeScope($0 ? .global : .local) }
                )) {
                    Label("Whole Vault", systemImage: "circle.hexagongrid")
                }
                .toggleStyle(.button)
                .help("Show every note in the vault instead of only the notes linked to the selected one")
            }

            if let subgraph, subgraph.nodes.isEmpty == false {
                HStack(spacing: 12) {
                    Text(countText(for: subgraph))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    GraphLegendBar(subgraph: subgraph)
                }
            }
        }
    }

    private func countText(for subgraph: NoteGraphSubgraph) -> String {
        let notes = subgraph.nodes.count == 1 ? "1 note" : "\(subgraph.nodes.count) notes"
        let links = subgraph.edges.count == 1 ? "1 link" : "\(subgraph.edges.count) links"
        return "\(notes), \(links)"
    }

    private var isFiltered: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var headerSubtitle: String {
        switch graphScope {
        case .local:
            if let selectedNode {
                return "Notes linked to and from “\(selectedNode.title)”."
            }
            return "Select a note to see what it links to."
        case .global:
            return isFiltered
                ? "Every note matching “\(searchText)”, coloured by folder."
                : "Every note in the vault, coloured by folder."
        }
    }

    private var emptyState: some View {
        Text(graphScope == .local
            ? "Nothing to draw yet. Select a note, or turn on Whole Vault."
            : isFiltered ? "No notes match “\(searchText)”." : "No links to draw yet.")
            .font(.system(size: 15, design: .serif).italic())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GraphCanvasPanel: View {
    let snapshot: VaultSnapshot
    let subgraph: NoteGraphSubgraph
    let graphScope: GraphScope
    let selectedNoteID: String?
    let onSelectNote: (String) -> Void

    @State private var hoveredNodeID: String?

    var body: some View {
        GeometryReader { geometry in
            let positions = GraphLayoutEngine.positions(
                for: subgraph,
                snapshot: snapshot,
                scope: graphScope,
                size: geometry.size
            )

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(VisualTheme.heroSurface)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VisualTheme.shade.opacity(0.05), lineWidth: 1)

                Canvas { context, size in
                    drawCanvasBackground(context: &context, size: size)
                    drawEdges(context: &context, positions: positions)
                }

                ForEach(subgraph.nodes) { node in
                    let isSelected = node.id == selectedNoteID
                    let isHovered = node.id == hoveredNodeID
                    let isHighlighted = subgraph.highlightedNodeIDs.contains(node.id)
                    let isAdjacentToSelection = selectedNoteID.map {
                        snapshot.noteGraph.adjacentNoteIDs(for: $0).contains(node.id)
                    } ?? false

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            onSelectNote(node.id)
                        }
                    } label: {
                        GraphNodeView(
                            node: node,
                            color: GraphPalette.color(for: node.folderPath),
                            scope: graphScope,
                            isSelected: isSelected,
                            isHighlighted: isHighlighted,
                            isAdjacentToSelection: isAdjacentToSelection,
                            isHovered: isHovered
                        )
                    }
                    .buttonStyle(.plain)
                    .position(positions[node.id] ?? CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2))
                    .onHover { hovering in
                        hoveredNodeID = hovering ? node.id : nil
                    }
                }
            }
        }
        .frame(minHeight: 640)
        .shadow(color: Color.black.opacity(0.06), radius: 24, x: 0, y: 14)
    }

    private func drawCanvasBackground(context: inout GraphicsContext, size: CGSize) {
        let gridSpacing: CGFloat = 64
        var gridPath = Path()
        var x: CGFloat = gridSpacing
        while x < size.width {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
            x += gridSpacing
        }

        var y: CGFloat = gridSpacing
        while y < size.height {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
            y += gridSpacing
        }

        context.stroke(
            gridPath,
            with: .color(VisualTheme.shade.opacity(0.025)),
            lineWidth: 1
        )

        let glowRect = CGRect(
            x: size.width * 0.52,
            y: size.height * 0.08,
            width: size.width * 0.34,
            height: size.height * 0.26
        )
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [VisualTheme.panel.opacity(0.32), .clear]),
                center: CGPoint(x: glowRect.midX, y: glowRect.midY),
                startRadius: 12,
                endRadius: max(glowRect.width, glowRect.height) / 2
            )
        )
    }

    private func drawEdges(
        context: inout GraphicsContext,
        positions: [String: CGPoint]
    ) {
        for edge in subgraph.edges {
            guard let start = positions[edge.sourceID], let end = positions[edge.targetID] else {
                continue
            }

            let isSelectedEdge = selectedNoteID == edge.sourceID || selectedNoteID == edge.targetID
            let isHighlightedEdge = subgraph.highlightedNodeIDs.contains(edge.sourceID)
                || subgraph.highlightedNodeIDs.contains(edge.targetID)

            var path = Path()
            path.move(to: start)
            path.addQuadCurve(
                to: end,
                control: curvedControlPoint(start: start, end: end)
            )

            context.stroke(
                path,
                with: .color(
                    isSelectedEdge
                        ? Color(red: 0.30, green: 0.45, blue: 0.72).opacity(0.45)
                        : isHighlightedEdge
                            ? Color(red: 0.36, green: 0.51, blue: 0.38).opacity(0.28)
                            : VisualTheme.shade.opacity(0.08)
                ),
                style: StrokeStyle(
                    lineWidth: isSelectedEdge ? 2.2 : 1,
                    lineCap: .round
                )
            )
        }
    }

    private func curvedControlPoint(start: CGPoint, end: CGPoint) -> CGPoint {
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let distance = max(hypot(delta.x, delta.y), 1)
        let normal = CGPoint(x: -delta.y / distance, y: delta.x / distance)
        let curveAmount = min(max(distance * 0.08, 12), 42)
        return CGPoint(
            x: midpoint.x + normal.x * curveAmount,
            y: midpoint.y + normal.y * curveAmount
        )
    }

}

enum GraphPalette {
    static func color(for folderPath: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.28, green: 0.47, blue: 0.72),
            Color(red: 0.27, green: 0.58, blue: 0.46),
            Color(red: 0.73, green: 0.48, blue: 0.19),
            Color(red: 0.57, green: 0.38, blue: 0.68),
            Color(red: 0.64, green: 0.32, blue: 0.31),
            Color(red: 0.36, green: 0.54, blue: 0.26),
        ]

        let bucket = folderPath.split(separator: "/").first.map(String.init) ?? "Vault Root"
        return palette[StablePaletteIndex.index(for: bucket, modulo: palette.count)]
    }

    static func bucketName(for folderPath: String) -> String {
        folderPath.split(separator: "/").first.map(String.init) ?? "Vault Root"
    }
}

private struct GraphLegendBar: View {
    let subgraph: NoteGraphSubgraph

    private var buckets: [GraphLegendBucket] {
        let grouped = Dictionary(grouping: subgraph.nodes) { node in
            GraphPalette.bucketName(for: node.folderPath)
        }

        return grouped.map { bucket, nodes in
            GraphLegendBucket(name: bucket, count: nodes.count, color: GraphPalette.color(for: bucket))
        }.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(buckets.prefix(6)) { bucket in
                Circle()
                    .fill(bucket.color)
                    .frame(width: 11, height: 11)
                    .overlay(
                        Circle()
                            .stroke(VisualTheme.panel.opacity(0.7), lineWidth: 1)
                    )
                    .help("\(bucket.name): \(bucket.count) notes")
            }

            if buckets.count > 6 {
                Text("+\(buckets.count - 6)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Folder colours: " + buckets.prefix(6).map(\.name).joined(separator: ", "))
    }
}

private struct GraphLegendBucket: Identifiable {
    let name: String
    let count: Int
    let color: Color

    var id: String { name }
}

enum StablePaletteIndex {
    static func index(for value: String, modulo count: Int) -> Int {
        guard count > 0 else { return 0 }

        var hash: UInt64 = 1_469_598_103_934_665_603
        for scalar in value.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }

        return Int(hash % UInt64(count))
    }
}

private struct GraphNodeView: View {
    let node: NoteGraphNode
    let color: Color
    let scope: GraphScope
    let isSelected: Bool
    let isHighlighted: Bool
    let isAdjacentToSelection: Bool
    let isHovered: Bool

    var body: some View {
        Group {
            if showsLabel {
                HStack(spacing: 10) {
                    Circle()
                        .fill(nodeFill)
                        .frame(width: nodeDiameter, height: nodeDiameter)
                        .overlay(
                            Circle()
                                .stroke(nodeStroke, lineWidth: isSelected ? 2.4 : 1.2)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.title)
                            .font(.system(size: isSelected ? 14 : 12, weight: .bold))
                            .lineLimit(1)

                        Text(node.folderPath.isEmpty ? "Vault Root" : node.folderPath)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(VisualTheme.panel.opacity(isSelected ? 0.96 : 0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(nodeStroke.opacity(0.35), lineWidth: isSelected ? 1.6 : 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
            } else {
                Circle()
                    .fill(nodeFill)
                    .frame(width: nodeDiameter, height: nodeDiameter)
                    .overlay(
                        Circle()
                            .stroke(nodeStroke.opacity(0.45), lineWidth: isHighlighted ? 1.2 : 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isSelected ? 1.08 : isHovered ? 1.04 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isSelected)
        .animation(.easeInOut(duration: 0.14), value: isHovered)
    }

    private var showsLabel: Bool {
        scope == .local || isSelected || isHighlighted || isHovered
    }

    private var nodeFill: Color {
        if isSelected {
            return color.opacity(0.94)
        }
        if isHighlighted {
            return color.opacity(0.76)
        }
        if isAdjacentToSelection {
            return color.opacity(0.54)
        }
        return color.opacity(scope == .global ? 0.34 : 0.46)
    }

    private var nodeStroke: Color {
        if isSelected {
            return VisualTheme.shade.opacity(0.82)
        }
        if isHighlighted {
            return color
        }
        return VisualTheme.shade.opacity(0.28)
    }

    private var nodeDiameter: CGFloat {
        if isSelected {
            return 18
        }
        if isHighlighted || isAdjacentToSelection {
            return 14
        }
        return scope == .global ? 10 : 12
    }
}

private struct GraphInspectorPanel: View {
    let snapshot: VaultSnapshot
    let selectedNode: NoteGraphNode?
    let graphScope: GraphScope
    let searchText: String
    let onSelectNote: (String) -> Void
    let onOpenReader: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let selectedNode {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedNode.title)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .help(selectedNode.relativePath)

                    Text(statsText(for: selectedNode))
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(.secondary)

                    Button("Open in Reader", action: onOpenReader)
                        .padding(.top, 4)
                }

                connectionsSection(
                    title: "Backlinks",
                    noteIDs: snapshot.noteGraph.inboundNoteIDs(to: selectedNode.id)
                )

                connectionsSection(
                    title: "Links from here",
                    noteIDs: snapshot.noteGraph.outboundNoteIDs(from: selectedNode.id)
                )
            } else {
                Text("Select a note in the graph.")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 270, alignment: .topLeading)
        .premiumPanel(cornerRadius: 10)
    }

    private func statsText(for node: NoteGraphNode) -> String {
        func count(_ value: Int, _ one: String, _ many: String) -> String { value == 1 ? "1 \(one)" : "\(value) \(many)" }
        return [
            count(node.inboundCount, "backlink", "backlinks"),
            count(node.outboundCount, "link", "links"),
            count(node.wordCount, "word", "words"),
        ].joined(separator: ", ")
    }

    @ViewBuilder
    private func connectionsSection(title: String, noteIDs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, design: .serif).italic())
                .foregroundStyle(.secondary)

            if noteIDs.isEmpty {
                Text("None")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(noteIDs.prefix(7), id: \.self) { noteID in
                    Button(snapshot.note(withID: noteID)?.title ?? noteID) {
                        onSelectNote(noteID)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .help(noteID)
                }
                if noteIDs.count > 7 {
                    Text("and \(noteIDs.count - 7) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private enum GraphLayoutEngine {
    static func positions(
        for subgraph: NoteGraphSubgraph,
        snapshot: VaultSnapshot,
        scope: GraphScope,
        size: CGSize
    ) -> [String: CGPoint] {
        switch scope {
        case .local:
            return localPositions(for: subgraph, snapshot: snapshot, size: size)
        case .global:
            return globalPositions(for: subgraph, size: size)
        }
    }

    private static func localPositions(
        for subgraph: NoteGraphSubgraph,
        snapshot: VaultSnapshot,
        size: CGSize
    ) -> [String: CGPoint] {
        guard let centerID = subgraph.centerNodeID else {
            return globalPositions(for: subgraph, size: size)
        }

        var positions = [String: CGPoint]()
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        positions[centerID] = center

        let incoming = Set(snapshot.noteGraph.inboundNoteIDs(to: centerID))
        let outgoing = Set(snapshot.noteGraph.outboundNoteIDs(from: centerID))

        let neighbors = subgraph.nodes
            .filter { $0.id != centerID }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let bidirectional = neighbors.filter { incoming.contains($0.id) && outgoing.contains($0.id) }
        let incomingOnly = neighbors.filter { incoming.contains($0.id) && outgoing.contains($0.id) == false }
        let outgoingOnly = neighbors.filter { outgoing.contains($0.id) && incoming.contains($0.id) == false }
        let peripheral = neighbors.filter {
            incoming.contains($0.id) == false && outgoing.contains($0.id) == false
        }

        assign(
            nodes: bidirectional,
            to: &positions,
            center: center,
            radius: min(size.width, size.height) * 0.22,
            startAngle: -.pi * 0.78,
            endAngle: -.pi * 0.22
        )
        assign(
            nodes: outgoingOnly,
            to: &positions,
            center: center,
            radius: min(size.width, size.height) * 0.26,
            startAngle: -.pi * 0.18,
            endAngle: .pi * 0.24
        )
        assign(
            nodes: incomingOnly,
            to: &positions,
            center: center,
            radius: min(size.width, size.height) * 0.26,
            startAngle: .pi * 0.76,
            endAngle: .pi * 1.22
        )
        assign(
            nodes: peripheral,
            to: &positions,
            center: center,
            radius: min(size.width, size.height) * 0.37,
            startAngle: .pi * 0.32,
            endAngle: .pi * 2.08
        )

        return positions
    }

    private static func globalPositions(
        for subgraph: NoteGraphSubgraph,
        size: CGSize
    ) -> [String: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let grouped = Dictionary(grouping: subgraph.nodes) { node in
            node.folderPath.split(separator: "/").first.map(String.init) ?? "Vault Root"
        }
        let groupKeys = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let clusterRadius = min(size.width, size.height) * 0.28

        var positions = [String: CGPoint]()
        for (groupIndex, groupKey) in groupKeys.enumerated() {
            let groupCenter: CGPoint
            if groupKeys.count == 1 {
                groupCenter = center
            } else {
                let angle = (-CGFloat.pi / 2) + (CGFloat(groupIndex) / CGFloat(groupKeys.count)) * CGFloat.pi * 2
                groupCenter = CGPoint(
                    x: center.x + cos(angle) * clusterRadius,
                    y: center.y + sin(angle) * clusterRadius * 0.72
                )
            }

            let groupNodes = (grouped[groupKey] ?? []).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

            if groupNodes.count == 1, let node = groupNodes.first {
                positions[node.id] = groupCenter
                continue
            }

            let groupSpread = max(44, min(130, CGFloat(sqrt(Double(groupNodes.count))) * 30))
            for (nodeIndex, node) in groupNodes.enumerated() {
                let ring = nodeIndex / 8
                let slot = nodeIndex % 8
                let slotCount = min(max(groupNodes.count - (ring * 8), 1), 8)
                let angle = (-CGFloat.pi / 2) + (CGFloat(slot) / CGFloat(slotCount)) * CGFloat.pi * 2
                let radius = groupSpread + CGFloat(ring) * 34
                positions[node.id] = CGPoint(
                    x: groupCenter.x + cos(angle) * radius,
                    y: groupCenter.y + sin(angle) * radius * 0.78
                )
            }
        }

        return positions
    }

    private static func assign(
        nodes: [NoteGraphNode],
        to positions: inout [String: CGPoint],
        center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) {
        guard nodes.isEmpty == false else { return }

        if nodes.count == 1, let node = nodes.first {
            positions[node.id] = CGPoint(
                x: center.x + cos((startAngle + endAngle) / 2) * radius,
                y: center.y + sin((startAngle + endAngle) / 2) * radius
            )
            return
        }

        for (index, node) in nodes.enumerated() {
            let progress = CGFloat(index) / CGFloat(max(nodes.count - 1, 1))
            let angle = startAngle + ((endAngle - startAngle) * progress)
            positions[node.id] = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }
}
