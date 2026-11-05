import Foundation

actor SubagentScanner {
    nonisolated struct SessionRef: Sendable, Equatable {
        let id: String
        let cwd: String
        let startedAt: Date?

        init(id: String, cwd: String, startedAt: Date? = nil) {
            self.id = id
            self.cwd = cwd
            self.startedAt = startedAt
        }

        init?(entry: JSON) {
            guard let id = entry["sessionId"] as? String, !id.isEmpty else { return nil }
            self.init(id: id, cwd: entry["cwd"] as? String ?? "", startedAt: (entry["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) })
        }
    }

    nonisolated struct Agent: Sendable, Equatable {
        enum State: String, Sendable { case running, done, failed, stopped }

        var id: String
        var title: String
        var type: String
        var state: State
        var startedAt: Date
        var updatedAt: Date
        var activity: String?
        var summary: String?
        var depth: Int
        var parentId: String?
        var background: Bool
        var worktree: Bool

        var json: JSON {
            [
                "id": id, "title": title, "type": type, "state": state.rawValue,
                "startedAt": startedAt.timeIntervalSince1970, "updatedAt": updatedAt.timeIntervalSince1970,
                "activity": activity ?? NSNull(), "summary": summary ?? NSNull(),
                "depth": depth, "parentId": parentId ?? NSNull(), "background": background, "worktree": worktree,
            ]
        }
    }

    nonisolated struct Report: Sendable, Equatable {
        var agents: [Agent] = []
        var older = 0
    }

    nonisolated struct Meta: Sendable, Equatable {
        var title = ""
        var type = "general-purpose"
        var depth = 1
        var parentId: String?
        var finished = false
        var stoppedByUser = false
        var background = false
        var worktree = false

        init() {}

        init(json: JSON) {
            title = json["description"] as? String ?? ""
            type = json["agentType"] as? String ?? type
            depth = max(json["spawnDepth"] as? Int ?? 1, 1)
            parentId = json["parentAgentId"] as? String
            finished = json["finished"] as? Bool ?? false
            stoppedByUser = json["stoppedByUser"] as? Bool ?? false
            background = json["requestShape"] as? String == "background"
            worktree = json["spawnedWithWorktree"] as? Bool ?? false
        }
    }

    nonisolated struct Tail: Sendable, Equatable {
        enum Ending: Sendable, Equatable { case done, failed, stopped, quiet }

        var ending: Ending?
        var activity: String?
        var summary: String?
    }

    nonisolated struct Stamp: Sendable, Equatable {
        var modified: Date
        var created: Date
        var size: Int
    }

    private struct Cached {
        var meta: Stamp?
        var transcript: Stamp?
        var parsedMeta: Meta
        var tail: Tail
    }

    static let keepFinished: TimeInterval = 30 * 60
    static let staleAfter: TimeInterval = 60 * 60
    static let resumeSlack: TimeInterval = 60
    static let quietAfter: TimeInterval = 120
    static let maxListed = 24
    static let tailBytes = 64 * 1024
    static let maxTailBytes = 4 << 20
    static let searchInterval: TimeInterval = 60
    static let handbackTool = "SubagentHandback"

    let projectsDir: URL
    private var directories: [String: URL] = [:]
    private var searchedAt: [String: Date] = [:]
    private var cache: [String: Cached] = [:]

    init(projectsDir: URL) {
        self.projectsDir = projectsDir
    }

    func scan(_ sessions: [SessionRef], now: Date = .now) -> [String: Report] {
        var reports: [String: Report] = [:]
        var seen: Set<String> = []
        for session in sessions {
            guard let directory = directory(for: session, now: now)?.appending(path: "subagents") else { continue }
            reports[session.id] = report(in: directory, session: session, now: now, seen: &seen)
        }
        cache = cache.filter { seen.contains($0.key) }
        return reports
    }

    private func report(in directory: URL, session: SessionRef, now: Date, seen: inout Set<String>) -> Report {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        var metas: [String: (URL, Stamp)] = [:]
        var transcripts: [String: (URL, Stamp)] = [:]
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("agent-"), let stamp = Self.stamp(of: file) else { continue }
            if name.hasSuffix(".meta.json") {
                metas[String(name.dropFirst(6).dropLast(10))] = (file, stamp)
            } else if name.hasSuffix(".jsonl") {
                transcripts[String(name.dropFirst(6).dropLast(6))] = (file, stamp)
            }
        }
        let agents = Set(metas.keys).union(transcripts.keys).compactMap { id -> Agent? in
            let key = directory.path + "/" + id
            seen.insert(key)
            let meta = metas[id]
            let transcript = transcripts[id]
            var entry = cache[key] ?? Cached(parsedMeta: Meta(), tail: Tail())
            if entry.meta != meta?.1 {
                entry.parsedMeta = meta.flatMap { Self.readJSON($0.0) }.map(Meta.init(json:)) ?? Meta()
                entry.meta = meta?.1
            }
            if entry.transcript != transcript?.1 {
                entry.tail = transcript.map { Self.readTail(of: $0.0, size: $0.1.size) } ?? Tail()
                entry.transcript = transcript?.1
            }
            cache[key] = entry
            guard let stamp = transcript?.1 ?? meta?.1 else { return nil }
            return Self.agent(id: id, meta: entry.parsedMeta, tail: entry.tail, transcript: stamp, metaModified: meta?.1.modified,
                              sessionStart: session.startedAt, now: now)
        }
        return Self.arrange(agents, now: now)
    }

    private func directory(for session: SessionRef, now: Date) -> URL? {
        if let known = directories[session.id] { return known }
        let direct = projectsDir.appending(path: Self.projectName(for: session.cwd)).appending(path: session.id)
        if FileManager.default.fileExists(atPath: direct.path) {
            directories[session.id] = direct
            return direct
        }
        guard now.timeIntervalSince(searchedAt[session.id] ?? .distantPast) >= Self.searchInterval else { return nil }
        searchedAt[session.id] = now
        let projects = (try? FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        let found = projects.map { $0.appending(path: session.id) }.first { FileManager.default.fileExists(atPath: $0.path) }
        directories[session.id] = found
        return found
    }

    nonisolated static func projectName(for cwd: String) -> String {
        String(cwd.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
    }

    nonisolated static func agent(id: String, meta: Meta, tail: Tail, transcript: Stamp, metaModified: Date?, sessionStart: Date?, now: Date) -> Agent {
        let state: Agent.State
        if meta.stoppedByUser {
            state = .stopped
        } else if let ending = tail.ending, ending != .quiet || now.timeIntervalSince(transcript.modified) >= quietAfter {
            state = switch ending {
            case .failed: .failed
            case .stopped: .stopped
            case .done, .quiet: .done
            }
        } else if meta.finished, (metaModified ?? .distantPast) >= transcript.modified.addingTimeInterval(-resumeSlack) {
            state = .done
        } else if let sessionStart, transcript.modified < sessionStart {
            state = .stopped
        } else if now.timeIntervalSince(transcript.modified) >= staleAfter {
            state = .stopped
        } else {
            state = .running
        }
        return Agent(
            id: id,
            title: meta.title.isEmpty ? meta.type : meta.title,
            type: meta.type,
            state: state,
            startedAt: min(transcript.created, transcript.modified),
            updatedAt: transcript.modified,
            activity: tail.activity,
            summary: state == .running ? nil : tail.summary,
            depth: meta.depth,
            parentId: meta.parentId,
            background: meta.background,
            worktree: meta.worktree
        )
    }

    nonisolated static func arrange(_ agents: [Agent], now: Date) -> Report {
        let visible = agents.filter { $0.state == .running || now.timeIntervalSince($0.updatedAt) < keepFinished }
        let ids = Set(visible.map(\.id))
        let children = Dictionary(grouping: visible.filter { $0.parentId.map(ids.contains) == true }, by: { $0.parentId ?? "" })
        let ordered: ([Agent]) -> [Agent] = { group in
            group.sorted { left, right in
                if (left.state == .running) != (right.state == .running) { return left.state == .running }
                if left.state == .running { return (left.startedAt, left.id) < (right.startedAt, right.id) }
                return (left.updatedAt, left.id) > (right.updatedAt, right.id)
            }
        }
        var flat: [Agent] = []
        func append(_ group: [Agent], visited: Set<String>) {
            for agent in ordered(group) where !visited.contains(agent.id) {
                flat.append(agent)
                append(children[agent.id] ?? [], visited: visited.union([agent.id]))
            }
        }
        append(visible.filter { $0.parentId.map(ids.contains) != true }, visited: [])
        let listed = Array(flat.prefix(maxListed))
        return Report(agents: listed, older: agents.count - listed.count)
    }

    nonisolated static func readTail(of file: URL, size: Int) -> Tail {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return Tail() }
        defer { try? handle.close() }
        var length = min(tailBytes, size)
        while true {
            let offset = size - length
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil, let data = try? handle.read(upToCount: length) else { return Tail() }
            var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            if offset > 0, !lines.isEmpty { lines.removeFirst() }
            if let tail = parseTail(lines.reversed().lazy.map { Data($0) }, complete: offset == 0) { return tail }
            if offset == 0 || length >= maxTailBytes { return parseTail(lines.reversed().lazy.map { Data($0) }, complete: true) ?? Tail() }
            length = min(length * 4, size, maxTailBytes)
        }
    }

    nonisolated static func parseTail<Lines: Sequence>(_ newestFirst: Lines, complete: Bool) -> Tail? where Lines.Element == Data {
        var tail: Tail?
        for line in newestFirst {
            guard let entry = (try? JSONSerialization.jsonObject(with: line)) as? JSON,
                  let type = entry["type"] as? String, type == "assistant" || type == "user" else { continue }
            let message = entry["message"] as? JSON ?? [:]
            let blocks = message["content"] as? [JSON] ?? []
            let texts = blocks.compactMap { $0["text"] as? String } + [message["content"] as? String].compactMap(\.self)
            if tail == nil {
                let ending = ending(of: entry, type: type, message: message, blocks: blocks, texts: texts)
                tail = Tail(ending: ending, summary: type == "assistant" && ending != nil ? texts.first.flatMap(firstLine) : nil)
            }
            guard type == "assistant",
                  let use = blocks.last(where: { $0["type"] as? String == "tool_use" }), let name = use["name"] as? String else { continue }
            let input = use["input"] as? JSON ?? [:]
            tail?.activity = activity(name: name, input: input)
            if name == handbackTool, let report = (input["message"] as? String).flatMap(firstLine) {
                tail?.summary = report
            }
            return tail
        }
        return complete || tail?.ending != nil ? tail : nil
    }

    private nonisolated static func ending(of entry: JSON, type: String, message: JSON, blocks: [JSON], texts: [String]) -> Tail.Ending? {
        if type == "user" {
            if texts.contains(where: { $0.hasPrefix("[Request interrupted by user") }) { return .stopped }
            return entry["toolEndsTurn"] as? Bool == true ? .done : nil
        }
        if entry["isApiErrorMessage"] as? Bool == true { return .failed }
        guard !blocks.contains(where: { $0["type"] as? String == "tool_use" }) else { return nil }
        switch message["stop_reason"] as? String {
        case "end_turn", "stop_sequence": return .done
        case nil: return texts.isEmpty ? nil : .quiet
        default: return nil
        }
    }

    nonisolated static func activity(name: String, input: JSON) -> String {
        let tool = name.hasPrefix("mcp__") ? name.components(separatedBy: "__").last ?? name : name
        let file = (input["file_path"] as? String ?? input["notebook_path"] as? String).map { ($0 as NSString).lastPathComponent }
        let text: String
        switch name {
        case handbackTool:
            text = String(localized: "Bericht abgegeben")
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit":
            text = file.map { "\(tool) \($0)" } ?? tool
        case "Bash":
            let command = (input["command"] as? String).map(trimmedCommand)
            text = labelled(tool, (input["description"] as? String).flatMap(plainLine) ?? command.flatMap(plainLine))
        case "Grep", "Glob":
            text = labelled(tool, input["pattern"] as? String)
        case "WebFetch":
            text = labelled(tool, (input["url"] as? String).flatMap { URL(string: $0)?.host() })
        case "WebSearch":
            text = labelled(tool, input["query"] as? String)
        case "Agent", "Task":
            text = labelled("Agent", input["description"] as? String)
        case "Skill":
            text = labelled(tool, input["skill"] as? String)
        default:
            text = labelled(tool, file)
        }
        return String(text.prefix(140))
    }

    private nonisolated static func labelled(_ tool: String, _ detail: String?) -> String {
        guard let detail = detail.flatMap(plainLine) else { return tool }
        return "\(tool): \(detail)"
    }

    private nonisolated static func trimmedCommand(_ command: String) -> String {
        let parts = command.components(separatedBy: "&&").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.first { !$0.hasPrefix("cd ") && !$0.isEmpty } ?? command
    }

    private nonisolated static func plainLine(_ text: String) -> String? {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    nonisolated static func firstLine(_ text: String) -> String? {
        let decoration = CharacterSet(charactersIn: "#*_`>- ")
        let line = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: decoration).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line.map { String($0.prefix(160)) }
    }

    private nonisolated static func readJSON(_ file: URL) -> JSON? {
        (try? Data(contentsOf: file)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? JSON }
    }

    private nonisolated static func stamp(of file: URL) -> Stamp? {
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate else { return nil }
        return Stamp(modified: modified, created: values.creationDate ?? modified, size: values.fileSize ?? 0)
    }
}
