import Foundation

actor TodoScanner {
    nonisolated struct Todo: Sendable, Equatable {
        enum State: String, Sendable { case pending, inProgress = "in_progress", completed }

        var content: String
        var activeForm: String?
        var state: State

        var json: JSON { ["content": content, "activeForm": activeForm ?? NSNull(), "state": state.rawValue] }
    }

    private struct Cached {
        var modified: Date
        var size: Int
        var todos: [Todo]
    }

    static let toolName = "TodoWrite"
    static let tailBytes = 256 * 1024
    static let maxTailBytes = 4 << 20
    static let maxTodos = 40

    let projectsDir: URL
    private var cache: [String: Cached] = [:]

    init(projectsDir: URL) {
        self.projectsDir = projectsDir
    }

    func scan(_ sessions: [SubagentScanner.SessionRef]) -> [String: [Todo]] {
        var result: [String: [Todo]] = [:]
        for session in sessions {
            let file = projectsDir.appending(path: SubagentScanner.projectName(for: session.cwd)).appending(path: "\(session.id).jsonl")
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate else { continue }
            let size = values.fileSize ?? 0
            if let cached = cache[session.id], cached.modified == modified, cached.size == size {
                result[session.id] = cached.todos
                continue
            }
            let todos = Self.readTodos(of: file, size: size)
            cache[session.id] = Cached(modified: modified, size: size, todos: todos)
            result[session.id] = todos
        }
        cache = cache.filter { result[$0.key] != nil }
        return result.filter { !$0.value.isEmpty }
    }

    nonisolated static func readTodos(of file: URL, size: Int) -> [Todo] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        var length = min(tailBytes, size)
        while true {
            let offset = size - length
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil, let data = try? handle.read(upToCount: length) else { return [] }
            var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            if offset > 0, !lines.isEmpty { lines.removeFirst() }
            if let todos = latestTodos(newestFirst: lines.reversed().lazy.map { Data($0) }) { return todos }
            if offset == 0 || length >= maxTailBytes { return [] }
            length = min(length * 4, size, maxTailBytes)
        }
    }

    nonisolated static func latestTodos<Lines: Sequence>(newestFirst: Lines) -> [Todo]? where Lines.Element == Data {
        for line in newestFirst {
            guard let entry = (try? JSONSerialization.jsonObject(with: line)) as? JSON, entry["type"] as? String == "assistant",
                  let blocks = (entry["message"] as? JSON)?["content"] as? [JSON],
                  let write = blocks.last(where: { $0["type"] as? String == "tool_use" && $0["name"] as? String == toolName }),
                  let items = (write["input"] as? JSON)?["todos"] as? [JSON] else { continue }
            return items.prefix(maxTodos).compactMap(todo(from:))
        }
        return nil
    }

    private nonisolated static func todo(from item: JSON) -> Todo? {
        guard let content = item["content"] as? String, !content.isEmpty else { return nil }
        return Todo(content: content, activeForm: item["activeForm"] as? String,
                    state: (item["status"] as? String).flatMap(Todo.State.init(rawValue:)) ?? .pending)
    }
}
