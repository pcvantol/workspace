import Foundation

struct WorklistGraphNode: Equatable {
    let item: ApprovedWorklistItem
    let column: Int
    let row: Int
    let contextOnly: Bool
}

struct WorklistGraphEdge: Equatable, Hashable {
    let predecessor: String
    let dependent: String
}

// Geometry only. Eligibility, release and serial dispatch always come from Forge.
struct WorklistGraphLayout: Equatable {
    let nodes: [WorklistGraphNode]
    let edges: [WorklistGraphEdge]
    let unresolvedDependencies: [String]
    static let nodeWidth = 248.0
    static let nodeHeight = 178.0
    static let columnStride = 320.0
    static let rowStride = 214.0

    var width: Double { Double((nodes.map(\.column).max() ?? 0)) * Self.columnStride + Self.nodeWidth + 32 }
    var topInset: Double { Double(edges.count) * 8 + 24 }
    var height: Double { Double((nodes.map(\.row).max() ?? 0)) * Self.rowStride + Self.nodeHeight + topInset + 16 }

    static func make(snapshot: ApprovedWorklistSnapshot, matching: Set<ApprovedWorklistKey>) -> Self? {
        guard snapshot.isCoherent(for: snapshot.scope), snapshot.items.count <= 64 else { return nil }
        let ordered = snapshot.items.sorted { $0.committedPosition < $1.committedPosition }
        let members = Dictionary(uniqueKeysWithValues: ordered.map { ($0.key.memberID, $0) })
        var columns: [String: Int] = [:]
        var rows: [Int: Int] = [:]
        var nodes: [WorklistGraphNode] = []
        var edges: [WorklistGraphEdge] = []
        var unresolved: Set<String> = []
        for item in ordered {
            guard item.dependencies.count <= 64, Set(item.dependencies).count == item.dependencies.count else { return nil }
            var column = 0
            for predecessor in item.dependencies {
                if let source = members[predecessor] {
                    guard source.committedPosition < item.committedPosition,
                          let precedingColumn = columns[predecessor] else { return nil }
                    column = max(column, precedingColumn + 1)
                    edges.append(WorklistGraphEdge(predecessor: predecessor, dependent: item.key.memberID))
                } else {
                    guard !snapshot.completeWithinScope else { return nil }
                    unresolved.insert(predecessor)
                }
            }
            columns[item.key.memberID] = column
            let row = rows[column, default: 0]
            rows[column] = row + 1
            nodes.append(WorklistGraphNode(item: item, column: column, row: row, contextOnly: !matching.contains(item.key)))
        }
        return Self(nodes: nodes, edges: edges, unresolvedDependencies: unresolved.sorted())
    }

    func route(_ edge: WorklistGraphEdge, index: Int) -> [CGPoint] {
        guard let from = nodes.first(where: { $0.item.key.memberID == edge.predecessor }),
              let to = nodes.first(where: { $0.item.key.memberID == edge.dependent }) else { return [] }
        let start = CGPoint(x: 16 + Double(from.column) * Self.columnStride + Self.nodeWidth,
                            y: topInset + Double(from.row) * Self.rowStride + Self.nodeHeight / 2)
        let end = CGPoint(x: 16 + Double(to.column) * Self.columnStride,
                          y: topInset + Double(to.row) * Self.rowStride + Self.nodeHeight / 2)
        let lane = topInset - 16 - Double(index) * 8
        return [start, CGPoint(x: start.x + 12, y: start.y), CGPoint(x: start.x + 12, y: lane),
                CGPoint(x: end.x - 12, y: lane), CGPoint(x: end.x - 12, y: end.y), end]
    }

    func adjacent(to key: ApprovedWorklistKey?, direction: Int) -> ApprovedWorklistKey? {
        guard !nodes.isEmpty else { return nil }
        guard let index = nodes.firstIndex(where: { $0.item.key == key }) else { return nodes.first?.item.key }
        return nodes[min(max(index + direction, 0), nodes.count - 1)].item.key
    }
}

struct WorklistGraphViewport {
    private(set) var zoom = 1.0
    mutating func magnify(_ factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        zoom = min(max(zoom * factor, 0.001), 2.0)
    }
    mutating func fit(layout: WorklistGraphLayout, width: Double, height: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        zoom = min(width / layout.width, height / layout.height, 1.0)
    }
}
