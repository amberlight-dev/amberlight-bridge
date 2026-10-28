import Foundation

typealias JSON = [String: Any]

final class Board {
    private final class Question {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let sessionId: String
        let kind: String
        let toolInput: JSON
        let items: [JSON]
        let detail: String?
        let createdAt: Date
        let expiresAt: Date
        var atMac = false
        var released = false
        var result: JSON?
        var waiter: CheckedContinuation<Void, Never>?

        init(sessionId: String, kind: String, toolInput: JSON, items: [JSON], detail: String?, wait: TimeInterval) {
            self.sessionId = sessionId
            self.kind = kind
            self.toolInput = toolInput
            self.items = items
            self.detail = detail
            createdAt = .now
            expiresAt = createdAt.addingTimeInterval(wait)
        }

        func wake() {
            waiter?.resume()
            waiter = nil
        }
    }

    static let standOnlineSeconds: TimeInterval = 10
    static let atMacExpirySeconds: TimeInterval = 600
    static let maxEvents = 50
    static let nextStepTool = "mcp__ccd_turn__wrap_up"

    let claudeDir: URL
    let standWaitSeconds: TimeInterval
    let replyLifetime: TimeInterval
    let doneDelay: TimeInterval
    private var questions: [String: Question] = [:]
    private var waiting: [String: JSON] = [:]
    private var codexSessions: [String: JSON] = [:]
    private var pendingDone: [String: UUID] = [:]
    private var events: [JSON] = []
    private var nextEventId = 1
    private var standSeenAt = Date.distantPast
    private var standAnswers = false

    init(claudeDir: URL, standWaitSeconds: TimeInterval = 120, replyLifetime: TimeInterval = 600, doneDelay: TimeInterval = 20) {
        self.claudeDir = claudeDir
        self.standWaitSeconds = standWaitSeconds
        self.replyLifetime = replyLifetime
        self.doneDelay = doneDelay
    }

    func handleHook(_ payload: JSON) async -> JSON {
        let event = payload["hook_event_name"] as? String
        let sessionId = payload["session_id"] as? String ?? ""
        let toolName = payload["tool_name"] as? String
        if payload["agent"] as? String == "codex" { trackCodex(event, sessionId: sessionId, payload: payload) }
        if event != "Stop" { pendingDone[sessionId] = nil }
        if event == "PreToolUse" && toolName == "AskUserQuestion" {
            return await ask(sessionId: sessionId, kind: "question", payload: payload)
        }
        if event == "PermissionRequest" {
            if toolName == "AskUserQuestion" { return [:] }
            return await ask(sessionId: sessionId, kind: "permission", payload: payload)
        }
        clearQuestions(of: sessionId)
        if event == "UserPromptSubmit" {
            waiting[sessionId] = nil
        } else if event == "PostToolUse" && toolName == Self.nextStepTool {
            noteNextStep(of: sessionId, payload["tool_input"] as? JSON ?? [:])
        } else if event == "Stop" {
            finishTurn(of: sessionId, message: payload["last_assistant_message"] as? String ?? "")
        }
        return [:]
    }

    func snapshot(standAnswers: Bool) -> JSON {
        standSeenAt = .now
        self.standAnswers = standAnswers
        expireQuestions()
        codexSessions = codexSessions.filter { Self.isAlive($0.value) }
        let registry = liveRegistry()
        forgetEndedSessions(live: Set(registry.compactMap { $0["sessionId"] as? String }))
        let pending = Dictionary(questions.values.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        let sessions = registry
            .map { sessionView($0, pending: pending) }
            .sorted { Self.sortKey($0) < Self.sortKey($1) }
        return ["sessions": sessions, "events": events]
    }

    func session(_ id: String) -> JSON? {
        liveRegistry().first { $0["sessionId"] as? String == id }
    }

    func answer(_ body: JSON) -> Bool {
        guard let id = body["questionId"] as? String, let question = questions[id], !question.atMac else { return false }
        if body["release"] as? Bool == true {
            question.released = true
        } else if question.kind == "question" {
            var updatedInput = question.toolInput
            updatedInput["answers"] = body["answers"] as? JSON ?? [:]
            question.result = ["hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": updatedInput,
            ]]
        } else {
            var decision: JSON = ["behavior": body["decision"] as? String == "allow" ? "allow" : "deny"]
            if decision["behavior"] as? String == "deny" { decision["message"] = String(localized: "In Amberlight abgelehnt.") }
            question.result = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        }
        question.wake()
        return true
    }

    private func ask(sessionId: String, kind: String, payload: JSON) async -> JSON {
        let toolInput = payload["tool_input"] as? JSON ?? [:]
        let question = Question(
            sessionId: sessionId,
            kind: kind,
            toolInput: toolInput,
            items: Self.questionItems(kind: kind, payload: payload),
            detail: kind == "permission" ? Self.permissionDetail(toolInput) : nil,
            wait: standWaitSeconds
        )
        supersedeQuestions(of: sessionId)
        questions[question.id] = question
        emit(sessionId, kind, question.items.first?["text"] as? String ?? "")
        guard isStandAnswering else {
            question.atMac = true
            return [:]
        }
        let timeout = Task { [standWaitSeconds] in
            try? await Task.sleep(for: .seconds(standWaitSeconds))
            question.wake()
        }
        await withCheckedContinuation { question.waiter = $0 }
        timeout.cancel()
        guard let result = question.result else {
            question.atMac = true
            return [:]
        }
        questions[question.id] = nil
        emit(sessionId, "answered", "")
        return result
    }

    private func noteNextStep(of sessionId: String, _ toolInput: JSON) {
        let ask = (toolInput["ask"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty else { return }
        let actions = (toolInput["actions"] as? [JSON] ?? []).compactMap { action -> (String, String)? in
            guard let label = action["label"] as? String, !label.isEmpty else { return nil }
            let message = (action["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? label
            return (label, message)
        }
        waiting[sessionId] = [
            "id": UUID().uuidString, "text": ask, "options": actions.map(\.0), "replies": actions.map(\.1),
            "askedAt": Date.now.timeIntervalSince1970,
        ]
    }

    func redeemReply(of sessionId: String, noteId: String, option: Int) -> String? {
        guard let note = waiting[sessionId], note["id"] as? String == noteId, !isExpired(note),
              let replies = note["replies"] as? [String], replies.indices.contains(option) else { return nil }
        waiting[sessionId] = nil
        return replies[option]
    }

    private func isExpired(_ note: JSON) -> Bool {
        guard let askedAt = note["askedAt"] as? Double else { return false }
        return Date.now.timeIntervalSince1970 - askedAt >= replyLifetime
    }

    private func visible(_ note: JSON) -> JSON {
        guard isExpired(note) else { return note }
        var expired = note
        expired["options"] = [String]()
        expired["replies"] = [String]()
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

    private func clearQuestions(of sessionId: String) {
        questions = questions.filter { !($0.value.sessionId == sessionId && $0.value.atMac) }
    }

    private func forgetEndedSessions(live: Set<String>) {
        waiting = waiting.filter { live.contains($0.key) }
        questions = questions.filter { live.contains($0.value.sessionId) || !$0.value.atMac }
    }

    private func supersedeQuestions(of sessionId: String) {
        for old in questions.values where old.sessionId == sessionId {
            questions[old.id] = nil
            old.wake()
        }
    }

    private func expireQuestions() {
        let cutoff = Date.now.addingTimeInterval(-Self.atMacExpirySeconds)
        questions = questions.filter { !($0.value.atMac && $0.value.createdAt < cutoff) }
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

    private func sessionView(_ entry: JSON, pending: [String: Question]) -> JSON {
        let sessionId = entry["sessionId"] as? String ?? ""
        let question = pending[sessionId]
        let note = waiting[sessionId]
        let repo = ((entry["cwd"] as? String ?? "") as NSString).lastPathComponent
        let state = question != nil || note != nil ? "waitingForYou" : (entry["status"] as? String == "busy" ? "working" : "idle")
        let name = entry["name"] as? String ?? ""
        return [
            "id": sessionId,
            "agent": entry["agent"] as? String ?? "claude",
            "title": name.isEmpty ? repo : name,
            "repo": repo,
            "state": state,
            "updatedAt": (entry["statusUpdatedAt"] as? Double ?? 0) / 1000,
            "waiting": note.map(visible) ?? NSNull(),
            "question": question.map { question -> JSON in [
                "id": question.id,
                "kind": question.kind,
                "items": question.items,
                "detail": question.detail ?? NSNull(),
                "atMac": question.atMac,
                "expiresAt": question.expiresAt.timeIntervalSince1970,
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
        return String(last.prefix(240))
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
