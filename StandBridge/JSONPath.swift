import Foundation

nonisolated enum JSONPath {
    enum Segment: Equatable {
        case key(String)
        case index(Int)
    }

    static let maxLength = 512

    static func parse(_ path: String) -> [Segment]? {
        guard path.count <= maxLength else { return nil }
        var segments: [Segment] = []
        var rest = Substring(path.trimmingCharacters(in: .whitespaces))
        while !rest.isEmpty {
            if rest.first == "." {
                rest.removeFirst()
                guard !rest.isEmpty, rest.first != ".", rest.first != "[" else { return nil }
            }
            if rest.first == "[" {
                guard let (segment, remainder) = bracket(rest) else { return nil }
                segments.append(segment)
                rest = remainder
            } else {
                let end = rest.firstIndex { $0 == "." || $0 == "[" } ?? rest.endIndex
                segments.append(.key(String(rest[..<end])))
                rest = rest[end...]
            }
        }
        return segments
    }

    static func resolve(_ path: String, in root: Any) -> Any? {
        guard let segments = parse(path) else { return nil }
        return segments.reduce(Optional(root)) { node, segment in
            switch (segment, node) {
            case (.key(let key), let object as [String: Any]): object[key]
            case (.index(let index), let array as [Any]) where array.indices.contains(index): array[index]
            default: nil
            }
        }
    }

    static func appending(_ segment: Segment, to path: String) -> String {
        switch segment {
        case .index(let index): return path + "[\(index)]"
        case .key(let key) where isPlain(key): return path.isEmpty ? key : path + "." + key
        case .key(let key):
            let escaped = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return path + "[\"\(escaped)\"]"
        }
    }

    static func string(_ segments: some Sequence<Segment>) -> String {
        segments.reduce("") { appending($1, to: $0) }
    }

    static func elementSplit(_ path: String) -> (array: String, field: String)? {
        guard let segments = parse(path), let last = segments.lastIndex(where: { if case .index = $0 { true } else { false } }) else { return nil }
        return (string(segments[..<last]), string(segments[(last + 1)...]))
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let text as String: Double(text.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    static func text(_ value: Any?) -> String? {
        switch value {
        case nil, is NSNull: nil
        case let text as String: text
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): number.boolValue ? "true" : "false"
        case let number as NSNumber: number.stringValue
        case is [Any]: "Liste"
        case is [String: Any]: String(localized: "Objekt")
        default: nil
        }
    }

    static func isPresent(_ value: Any?) -> Bool {
        switch value {
        case nil, is NSNull: false
        case let text as String: !text.isEmpty
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): number.boolValue
        default: true
        }
    }

    private static func isPlain(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "$" || $0 == "@" }
    }

    private static func bracket(_ text: Substring) -> (Segment, Substring)? {
        var rest = text.dropFirst()
        if rest.first == "\"" {
            rest.removeFirst()
            var key = ""
            while let character = rest.first {
                rest.removeFirst()
                if character == "\\" {
                    guard let escaped = rest.first else { return nil }
                    key.append(escaped)
                    rest.removeFirst()
                } else if character == "\"" {
                    guard rest.first == "]" else { return nil }
                    return (.key(key), rest.dropFirst())
                } else {
                    key.append(character)
                }
            }
            return nil
        }
        guard let close = rest.firstIndex(of: "]"), let index = Int(rest[..<close]), index >= 0 else { return nil }
        return (.index(index), rest[rest.index(after: close)...])
    }
}
