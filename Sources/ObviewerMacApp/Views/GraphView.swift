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

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note Graph")
                        .font(.system(size: 38, weight: .bold, design: .serif))

                    Text(headerSubtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 20)

                Picker("Graph Scope", selection: Binding(
                    get: { graphScope },
                    set: onChangeScope
                )) {
                    ForEach(GraphScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if let subgraph {
                HStack(spacing: 10) {
                    graphPill(text: "\(subgraph.nodes.count) nodes", systemImage: "circle.grid.2x2")
                    graphPill(text: "\(subgraph.edges.count) edges", systemImage: "point.3.connected.trianglepath.dotted")
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        graphPill(text: "Filtered", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var headerSubtitle: String {
        switch graphScope {
        case .local:
            if let selectedNode {
                return "A one-hop neighborhood around \(selectedNode.title), including backlinks and outbound links."
            }
            return "Select a note to inspect its local link neighborhood."

        case .global:
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return "The full vault graph filtered by your current search query."
            }
            return "A vault-wide relationship map grouped visually by folder."
        }
    }

    private func graphPill(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.55))

            Text("No graph to show yet.")
                .font(.system(size: 24, weight: .bold, design: .serif))

            Text("Open a vault and select a note to render a real note graph.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
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
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.56))

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)

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
                        onSelectNote(node.id)
                    } label: {
                        GraphNodeView(
                            node: node,
                            color: folderColor(for: node.folderPath),
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
    }

    private func drawCanvasBackground(context: inout GraphicsContext, size: CGSize) {
        let glowRect = CGRect(
            x: size.width * 0.52,
            y: size.height * 0.08,
            width: size.width * 0.34,
            height: size.height * 0.26
        )
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.32), .clear]),
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
                            : Color.black.opacity(0.08)
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

    private func folderColor(for folderPath: String) -> Color {
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
                            .font(.system(size: isSelected ? 14 : 12, weight: .bold, design: .rounded))
                            .lineLimit(1)

                        Text(node.folderPath.isEmpty ? "Vault Root" : node.folderPath)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.96 : 0.88))
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
            return Color.black.opacity(0.82)
        }
        if isHighlighted {
            return color
        }
        return Color.black.opacity(0.28)
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
            HStack {
                Text("Inspector")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(graphScope.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.7))
                    )
            }

            if let selectedNode {
                VStack(alignment: .leading, spacing: 14) {
                    Text(selectedNode.title)
                        .font(.system(size: 28, weight: .bold, design: .serif))

                    Text(selectedNode.relativePath)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        statPill(text: "\(selectedNode.inboundCount) backlinks", systemImage: "arrow.down.left")
                        statPill(text: "\(selectedNode.outboundCount) links", systemImage: "arrow.up.right")
                    }

                    HStack(spacing: 8) {
                        statPill(text: "\(selectedNode.wordCount) words", systemImage: "text.word.spacing")
                        statPill(text: "\(selectedNode.tagCount) tags", systemImage: "tag")
                    }

                    Button("Open In Reader") {
                        onOpenReader()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                connectionsSection(
                    title: "Backlinks",
                    noteIDs: snapshot.noteGraph.inboundNoteIDs(to: selectedNode.id)
                )

                connectionsSection(
                    title: "Links From Here",
                    noteIDs: snapshot.noteGraph.outboundNoteIDs(from: selectedNode.id)
                )
            } else {
                Text("Select a note in the graph to inspect its connections and jump back into the reader.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Filter")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(searchText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 310, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func statPill(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
    }

    @ViewBuilder
    private func connectionsSection(title: String, noteIDs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            if noteIDs.isEmpty {
                Text("None")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(noteIDs.prefix(7), id: \.self) { noteID in
                    let label = snapshot.note(withID: noteID)?.title ?? noteID
                    Button {
                        onSelectNote(noteID)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(noteID)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
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
