import Foundation

typealias JSON = [String: Any]

final class Board {
    private final class Ask {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let createdAt = Date.now
        let kind: String
        let toolName: String
        let items: [JSON]
        let detail: String?
        let toolInput: JSON
        let toolUseId: String?
        var result: JSON = [:]
        var waiter: CheckedContinuation<Void, Never>?

        init(kind: String, toolName: String, items: [JSON], detail: String?, payload: JSON) {
            self.kind = kind
            self.toolName = toolName
            self.items = items
            self.detail = detail
            toolInput = payload["tool_input"] as? JSON ?? [:]
            toolUseId = payload["tool_use_id"] as? String
        }

        func resolve(_ result: JSON) {
            guard let waiter else { return }
            self.result = result
            waiter.resume()
            self.waiter = nil
        }

        func matches(_ payload: JSON) -> Bool {
            if let toolUseId, let other = payload["tool_use_id"] as? String { return toolUseId == other }
            let input = (payload["tool_input"] as? JSON ?? [:]).filter { $0.key != "answers" }
            return toolName == payload["tool_name"] as? String
                && NSDictionary(dictionary: toolInput.filter { $0.key != "answers" }).isEqual(NSDictionary(dictionary: input))
        }
    }

    private final class Parked {
        var waiter: CheckedContinuation<String?, Never>?

        func resolve(_ text: String?) {
            waiter?.resume(returning: text)
            waiter = nil
        }
    }

    static let standOnlineSeconds: TimeInterval = 10
    static let codexAskSeconds: TimeInterval = 120
    static let maxEvents = 50
    static let nextStepTool = "mcp__ccd_turn__wrap_up"
    static let subagentScanInterval: TimeInterval = 1
    static let maxQuestionLength = 240
    private static let resumingEvents: Set<String> = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest"]

    let claudeDir: URL
    let askSeconds: TimeInterval
    let parkSeconds: TimeInterval
    let replyLifetime: TimeInterval
    let doneDelay: TimeInterval
    let maxParked: Int
    private var asks: [String: [Ask]] = [:]
    private var waiting: [String: JSON] = [:]
    private var parked: [String: Parked] = [:]
    private var codexSessions: [String: JSON] = [:]
    private var pendingDone: [String: UUID] = [:]
    private var events: [JSON] = []
    private var nextEventId = 1
    private var standSeenAt = Date.distantPast
    private var standAnswers = false
    private let subagents: SubagentScanner
    private let todoScanner: TodoScanner
    private var todoReports: [String: [TodoScanner.Todo]] = [:]
    private var subagentReports: [String: SubagentScanner.Report] = [:]
    private var subagentScan: Task<Void, Never>?
    private var subagentsScannedAt = Date.distantPast

    init(claudeDir: URL, askSeconds: TimeInterval = 3590, parkSeconds: TimeInterval = 28790, replyLifetime: TimeInterval = 600,
         doneDelay: TimeInterval = 20, maxParked: Int = 64, sweepInterval: TimeInterval = 30) {
        self.claudeDir = claudeDir
        self.askSeconds = askSeconds
        self.parkSeconds = parkSeconds
        self.replyLifetime = replyLifetime
        self.doneDelay = doneDelay
        self.maxParked = maxParked
        subagents = SubagentScanner(projectsDir: claudeDir.appending(path: "projects"))
        todoScanner = TodoScanner(projectsDir: claudeDir.appending(path: "projects"))
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(sweepInterval))
                guard let self else { return }
                _ = sweepEndedSessions()
            }
        }
    }

    func handleHook(_ payload: JSON) async -> JSON {
        let event = payload["hook_event_name"] as? String ?? ""
        let sessionId = payload["session_id"] as? String ?? ""
        let toolName = payload["tool_name"] as? String
        let codex = payload["agent"] as? String == "codex"
        if codex { trackCodex(event, sessionId: sessionId, payload: payload) }
        if event != "Stop" { pendingDone[sessionId] = nil }
        if !codex && event == "PermissionRequest" {
            closeAsks(of: sessionId) { $0.matches(payload) }
        } else if !codex && event == "PostToolUse" {
            closeAsk(of: sessionId, ranBy: payload)
        } else if Self.resumingEvents.contains(event) || event == "Stop" {
            closeAsks(of: sessionId) { _ in true }
        }
        if Self.resumingEvents.contains(event) { resolveParked(of: sessionId, with: nil) }
        if event == "PermissionRequest" {
            return await ask(sessionId: sessionId, payload: payload, codex: codex)
        }
        if event == "UserPromptSubmit" {
            waiting[sessionId] = nil
        } else if event == "PostToolUse" && toolName == Self.nextStepTool {
            noteNextStep(of: sessionId, payload["tool_input"] as? JSON ?? [:])
        } else if event == "Stop" {
            finishTurn(of: sessionId, message: payload["last_assistant_message"] as? String ?? "")
        }
        return [:]
    }

    func awaitReply(_ payload: JSON) async -> String {
        _ = await handleHook(payload)
        let sessionId = payload["session_id"] as? String ?? ""
        guard payload["hook_event_name"] as? String == "Stop", payload["agent"] as? String != "codex", isLive(sessionId) else { return "" }
        return await park(sessionId) ?? ""
    }

    func hasPendingAsk(_ sessionId: String) -> Bool {
        asks[sessionId] != nil
    }

    private func isLive(_ sessionId: String) -> Bool {
        sweepEndedSessions().contains(sessionId)
    }

    private func sweepEndedSessions() -> Set<String> {
        let live = Set(liveRegistry().compactMap { $0["sessionId"] as? String })
        forgetEndedSessions(live: live)
        return live
    }

    private func closeAsks(of sessionId: String, where shouldClose: (Ask) -> Bool) {
        for ask in asks[sessionId] ?? [] where shouldClose(ask) {
            remove(ask, of: sessionId)
            ask.resolve([:])
        }
    }

    private func closeAsk(of sessionId: String, ranBy payload: JSON) {
        let open = asks[sessionId] ?? []
        guard let ask = open.first(where: { $0.matches(payload) }) else { return }
        remove(ask, of: sessionId)
        ask.resolve([:])
    }

    private func remove(_ ask: Ask, of sessionId: String) {
        asks[sessionId]?.removeAll { $0 === ask }
        if asks[sessionId]?.isEmpty == true { asks[sessionId] = nil }
    }

    private func park(_ sessionId: String) async -> String? {
        resolveParked(of: sessionId, with: nil)
        guard parked.count < maxParked else { return nil }
        let poll = Parked()
        parked[sessionId] = poll
        let timeout = Task { [weak self, parkSeconds] in
            try? await Task.sleep(for: .seconds(parkSeconds))
            if self?.parked[sessionId] === poll { self?.resolveParked(of: sessionId, with: nil) }
        }
        let reply = await withCheckedContinuation { poll.waiter = $0 }
        timeout.cancel()
        return reply
    }

    @discardableResult
    func resolveParked(of sessionId: String, with text: String?) -> Bool {
        guard let poll = parked.removeValue(forKey: sessionId) else { return false }
        poll.resolve(text)
        return true
    }

    private func ask(sessionId: String, payload: JSON, codex: Bool) async -> JSON {
        let toolName = payload["tool_name"] as? String ?? ""
        let kind = toolName == "AskUserQuestion" ? "question" : "permission"
        guard isLive(sessionId) else { return [:] }
        let ask = Ask(kind: kind, toolName: toolName, items: Self.questionItems(kind: kind, payload: payload),
                      detail: kind == "permission" ? Self.permissionDetail(payload["tool_input"] as? JSON ?? [:]) : nil, payload: payload)
        emit(sessionId, kind, ask.items.first?["text"] as? String ?? "")
        if codex && !isStandAnswering { return [:] }
        asks[sessionId, default: []].append(ask)
        let timeout = Task { [weak self, seconds = codex ? Self.codexAskSeconds : askSeconds] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.remove(ask, of: sessionId)
            ask.resolve([:])
        }
        await withCheckedContinuation { ask.waiter = $0 }
        timeout.cancel()
        return ask.result
    }

    func answer(_ body: JSON) -> Bool {
        guard let id = body["questionId"] as? String,
              let sessionId = asks.first(where: { $0.value.contains { $0.id == id } })?.key,
              let ask = asks[sessionId]?.first(where: { $0.id == id }), ask.waiter != nil else { return false }
        let decision: JSON
        if ask.kind == "question" {
            let given = body["answers"] as? JSON ?? [:]
            let answers = given.compactMapValues(Self.answerText)
            guard !answers.isEmpty, answers.count == given.count else { return false }
            decision = ["behavior": "allow", "updatedInput": ask.toolInput.merging(["answers": answers]) { $1 }]
        } else if body["decision"] as? String == "allow" {
            decision = ["behavior": "allow"]
        } else {
            decision = ["behavior": "deny", "message": String(localized: "In Amberlight abgelehnt.")]
        }
        remove(ask, of: sessionId)
        emit(sessionId, "answered", "")
        ask.resolve(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
        return true
    }

    private static func answerText(_ value: Any) -> String? {
        let text = (value as? [String])?.joined(separator: ", ") ?? (value as? String) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func freeTextReply(of sessionId: String, text: String) -> String {
        let question = waiting.removeValue(forKey: sessionId)?["text"] as? String
        guard let question else { return String(localized: "Nachricht des Users über Amberlight:\n\(text)") }
        return String(localized: "Antwort des Users über Amberlight auf „\(question)“:\n\(text)")
    }

    func snapshot(standAnswers: Bool) -> JSON {
        standSeenAt = .now
        self.standAnswers = standAnswers
        codexSessions = codexSessions.filter { Self.isAlive($0.value) }
        let registry = liveRegistry()
        forgetEndedSessions(live: Set(registry.compactMap { $0["sessionId"] as? String }))
        scanSubagents(registry)
        let sessions = registry
            .map(sessionView)
            .sorted { Self.sortKey($0) < Self.sortKey($1) }
        return ["sessions": sessions, "events": events]
    }

    func refreshSubagents() async {
        await subagentScan?.value
        let sessions = Self.subagentSessions(liveRegistry())
        subagentReports = await subagents.scan(sessions)
        todoReports = await todoScanner.scan(sessions)
        subagentsScannedAt = .now
    }

    private func scanSubagents(_ registry: [JSON]) {
        guard subagentScan == nil, Date.now.timeIntervalSince(subagentsScannedAt) >= Self.subagentScanInterval else { return }
        let sessions = Self.subagentSessions(registry)
        subagentScan = Task { [subagents, todoScanner] in
            let reports = await subagents.scan(sessions)
            let todos = await todoScanner.scan(sessions)
            self.subagentReports = reports
            self.todoReports = todos
            self.subagentsScannedAt = .now
            self.subagentScan = nil
        }
    }

    private static func subagentSessions(_ registry: [JSON]) -> [SubagentScanner.SessionRef] {
        registry.filter { $0["agent"] as? String != "codex" }.compactMap(SubagentScanner.SessionRef.init(entry:))
    }

    func session(_ id: String) -> JSON? {
        liveRegistry().first { $0["sessionId"] as? String == id }
    }

    private func noteNextStep(of sessionId: String, _ toolInput: JSON) {
        let ask = (toolInput["ask"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty else { return }
        let labels = (toolInput["actions"] as? [JSON] ?? []).compactMap { $0["label"] as? String }.filter { !$0.isEmpty }
        waiting[sessionId] = [
            "id": UUID().uuidString, "text": String(ask.prefix(Self.maxQuestionLength)), "options": labels,
            "askedAt": Date.now.timeIntervalSince1970,
        ]
    }

    func redeemReply(of sessionId: String, noteId: String, option: Int) -> String? {
        guard let note = waiting[sessionId], note["id"] as? String == noteId, !isExpired(note, of: sessionId),
              let options = note["options"] as? [String], options.indices.contains(option) else { return nil }
        waiting[sessionId] = nil
        return options[option]
    }

    private func isExpired(_ note: JSON, of sessionId: String) -> Bool {
        guard parked[sessionId] == nil, let askedAt = note["askedAt"] as? Double else { return false }
        return Date.now.timeIntervalSince1970 - askedAt >= replyLifetime
    }

    private func visible(_ note: JSON, of sessionId: String) -> JSON {
        guard isExpired(note, of: sessionId) else { return note }
        var expired = note
        expired["options"] = [String]()
        return expired
    }

    private func finishTurn(of sessionId: String, message: String) {
        if let question = Self.trailingQuestion(in: message) {
            waiting[sessionId] = ["text": question, "options": [String]()]
        }
        if let note = waiting[sessionId] {
            emit(sessionId, "waiting", note["text"] as? String ?? "")
        } else {
            scheduleDone(of: sessionId, summary: Self.summary(of: message))
        }
    }

    private func scheduleDone(of sessionId: String, summary: String) {
        let token = UUID()
        pendingDone[sessionId] = token
        Task { [weak self, doneDelay] in
            try? await Task.sleep(for: .seconds(doneDelay))
            self?.confirmDone(of: sessionId, token: token, summary: summary)
        }
    }

    private func confirmDone(of sessionId: String, token: UUID, summary: String) {
        guard pendingDone[sessionId] == token else { return }
        pendingDone[sessionId] = nil
        guard session(sessionId)?["status"] as? String != "busy" else { return }
        emit(sessionId, "done", summary)
    }

    private var isStandAnswering: Bool {
        standAnswers && Date.now.timeIntervalSince(standSeenAt) < Self.standOnlineSeconds
    }

    private func forgetEndedSessions(live: Set<String>) {
        for sessionId in parked.keys where !live.contains(sessionId) { resolveParked(of: sessionId, with: nil) }
        for sessionId in asks.keys where !live.contains(sessionId) { closeAsks(of: sessionId) { _ in true } }
        waiting = waiting.filter { live.contains($0.key) }
    }

    private func emit(_ sessionId: String, _ kind: String, _ text: String) {
        events.append(["id": nextEventId, "sessionId": sessionId, "kind": kind, "text": text, "at": Date.now.timeIntervalSince1970])
        events = events.suffix(Self.maxEvents)
        nextEventId += 1
    }

    private func liveRegistry() -> [JSON] {
        claudeRegistry() + codexSessions.values.filter(Self.isAlive)
    }

    private func claudeRegistry() -> [JSON] {
        let dir = claudeDir.appending(path: "sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let entry = try? JSONSerialization.jsonObject(with: data) as? JSON,
                  let pid = entry["pid"] as? Int32,
                  kill(pid, 0) == 0 else { return nil }
            return entry
        }
    }

    private func trackCodex(_ event: String?, sessionId: String, payload: JSON) {
        guard event != "SessionEnd" else {
            codexSessions[sessionId] = nil
            return
        }
        var entry = codexSessions[sessionId] ?? ["sessionId": sessionId, "agent": "codex"]
        if let cwd = payload["cwd"] as? String { entry["cwd"] = cwd }
        if let pid = payload["pid"] as? Int32 { entry["pid"] = pid }
        entry["status"] = ["Stop", "Interrupt", "SessionStart"].contains(event) ? "idle" : "busy"
        entry["statusUpdatedAt"] = Date.now.timeIntervalSince1970 * 1000
        codexSessions[sessionId] = entry
    }

    private static func isAlive(_ entry: JSON) -> Bool {
        guard let pid = entry["pid"] as? Int32 else { return true }
        return pid > 1 && kill(pid, 0) == 0
    }

    private func sessionView(_ entry: JSON) -> JSON {
        let sessionId = entry["sessionId"] as? String ?? ""
        let question = asks[sessionId]?.first
        let note = waiting[sessionId]
        let repo = ((entry["cwd"] as? String ?? "") as NSString).lastPathComponent
        let state = question != nil || note != nil ? "waitingForYou" : (entry["status"] as? String == "busy" ? "working" : "idle")
        let name = entry["name"] as? String ?? ""
        let report = subagentReports[sessionId] ?? SubagentScanner.Report()
        return [
            "id": sessionId,
            "agent": entry["agent"] as? String ?? "claude",
            "title": name.isEmpty ? repo : name,
            "repo": repo,
            "state": state,
            "updatedAt": (entry["statusUpdatedAt"] as? Double ?? 0) / 1000,
            "startedAt": (entry["startedAt"] as? Double).map { $0 / 1000 } ?? NSNull(),
            "subagents": report.agents.map(\.json),
            "subagentsOlder": report.older,
            "todos": (todoReports[sessionId] ?? []).map(\.json),
            "canReply": parked[sessionId] != nil,
            "waiting": note.map { visible($0, of: sessionId) } ?? NSNull(),
            "question": question.map { question -> JSON in [
                "id": question.id,
                "kind": question.kind,
                "items": question.items,
                "detail": question.detail ?? NSNull(),
                // NOTE: atMac/expiresAt only keep App 1.0 (15) decoding; drop once 1.1 is out.
                "atMac": false,
                "expiresAt": question.createdAt.addingTimeInterval(askSeconds).timeIntervalSince1970,
            ] } ?? NSNull(),
        ]
    }

    func statuslineUsage() -> JSON? {
        let file = claudeDir.appending(path: "stand-usage.json")
        guard let data = try? Data(contentsOf: file),
              let input = try? JSONSerialization.jsonObject(with: data) as? JSON else { return nil }
        let limits = input["rate_limits"] as? JSON ?? input
        let windows = [("five_hour", 300), ("seven_day", 10080)].compactMap { key, minutes -> JSON? in
            guard let window = limits[key] as? JSON, let used = window["used_percentage"] as? Double else { return nil }
            return ["minutes": minutes, "used": used / 100, "resetsAt": window["resets_at"] as? Double ?? NSNull()]
        }
        guard !windows.isEmpty else { return nil }
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return ["id": "claude", "name": "Claude", "windows": windows, "updatedAt": modified?.timeIntervalSince1970 ?? 0]
    }

    private static func sortKey(_ session: JSON) -> (Int, Double) {
        let rank = ["waitingForYou": 0, "working": 1][session["state"] as? String ?? ""] ?? 2
        return (rank, -(session["updatedAt"] as? Double ?? 0))
    }

    private static func summary(of message: String?) -> String {
        String((message ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500))
    }

    static func trailingQuestion(in message: String) -> String? {
        let decoration = CharacterSet(charactersIn: "*_`> ")
        let lines = message.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: decoration).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let last = lines.last(where: { !$0.isEmpty }), last.hasSuffix("?") else { return nil }
        return String(last.prefix(maxQuestionLength))
    }

    private static func questionItems(kind: String, payload: JSON) -> [JSON] {
        if kind == "permission" {
            return [[
                "header": String(localized: "Freigabe"),
                "text": String(localized: "\(payload["tool_name"] as? String ?? String(localized: "Werkzeug")) ausführen?"),
                "options": [["label": String(localized: "Erlauben")], ["label": String(localized: "Ablehnen")]],
                "multiSelect": false,
            ]]
        }
        let toolInput = payload["tool_input"] as? JSON ?? [:]
        return (toolInput["questions"] as? [JSON] ?? []).map { item in [
            "header": item["header"] as? String ?? "",
            "text": item["question"] as? String ?? "",
            "options": (item["options"] as? [JSON] ?? []).map { option -> JSON in
                ["label": option["label"] as? String ?? "", "description": option["description"] as? String ?? NSNull()]
            },
            "multiSelect": item["multiSelect"] as? Bool ?? false,
        ] }
    }

    private static func permissionDetail(_ toolInput: JSON) -> String {
        for key in ["command", "file_path", "url", "pattern", "path"] {
            if let value = toolInput[key], !"\(value)".isEmpty { return String("\(value)".prefix(400)) }
        }
        let data = (try? JSONSerialization.data(withJSONObject: toolInput, options: [.withoutEscapingSlashes])) ?? Data()
        return String((String(data: data, encoding: .utf8) ?? "").prefix(400))
    }
}
