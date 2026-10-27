import Foundation

nonisolated struct CustomNode: Codable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case vstack, hstack, zstack, spacer
        case text, symbol, dot, timer
        case ring, bar
        case line, bars, list
        case pill, divider

        var isContainer: Bool { self == .vstack || self == .hstack || self == .zstack }
    }

    enum Size: String, Codable {
        case xs, s, m, l, xl
    }

    enum Align: String, Codable {
        case leading, center, trailing
    }

    struct ToneRule: Codable, Equatable, Hashable {
        var when: String
        var tone: CustomWidgetDisplay.Tone
        var label: String?
    }

    static let maxNodes = 64
    static let maxDepth = 6

    var type: Kind
    var children: [CustomNode]?
    var text: String?
    var size: Size?
    var bold: Bool?
    var tone: CustomWidgetDisplay.Tone?
    var toneWhen: [ToneRule]?
    var when: String?
    var value: String?
    var max: String?
    var since: String?
    var plus: String?
    var plusUnit: String?
    var spacing: Double?
    var align: Align?
    var width: Double?
    var minW: Int?
    var minH: Int?
    var maxW: Int?
    var maxH: Int?
    var pulse: Bool?
    var progress: Double?
    var start: Date?
    var lines: Int?
    var priority: Int?
    var color: String?
    var ref: String?
}

nonisolated extension CustomNode {
    var nodeCount: Int { 1 + (children ?? []).reduce(0) { $0 + $1.nodeCount } }
    var depth: Int { 1 + ((children ?? []).map(\.depth).max() ?? 0) }
    var isTooComplex: Bool { nodeCount > Self.maxNodes || depth > Self.maxDepth }

    func contains(_ kind: Kind) -> Bool {
        type == kind || (children ?? []).contains { $0.contains(kind) }
    }
}
