import Foundation
import Observation

struct SecretVault {
    var read: (String) -> Data?
    var write: (Data, String) -> Void
    var delete: (String) -> Void

    static let keychain = SecretVault(read: { Keychain.read($0) }, write: { Keychain.write($0, for: $1) }, delete: { Keychain.delete($0) })

    static func memory() -> SecretVault {
        final class Box { var items: [String: Data] = [:] }
        let box = Box()
        return SecretVault(read: { box.items[$0] }, write: { box.items[$1] = $0 }, delete: { box.items[$0] = nil })
    }
}

@Observable
final class CustomWidgetStore {
    typealias Fetch = (URLRequest) async throws(CustomRequestError) -> CustomFetcher.Response

    static let historyLimit = 96

    static func file(forPort port: UInt16) -> URL {
        URL.applicationSupportDirectory.appending(path: port == LayoutStore.defaultPort ? "Stand Bridge/custom-widgets.json" : "Stand Bridge/custom-widgets-\(port).json")
    }

    static func secretKey(id: UUID, origin: String) -> String {
        "custom.\(id.uuidString).\(origin)"
    }

    private(set) var definitions: [CustomWidgetDefinition] = []
    @ObservationIgnored private(set) var revision = 0
    private(set) var displays: [UUID: CustomWidgetDisplay] = [:]
    @ObservationIgnored private(set) var history: [UUID: [CustomWidgetDisplay.Sample]] = [:]
    @ObservationIgnored var fetch: Fetch = { request throws(CustomRequestError) in try await CustomFetcher.fetch(request) }
    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let vault: SecretVault
    @ObservationIgnored private var fetchedAt: [UUID: Date] = [:]
    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var actionsInFlight: Set<UUID> = []
    @ObservationIgnored private var lastResults: [UUID: Any] = [:]

    private struct Saved: Codable {
        var definitions: [CustomWidgetDefinition]
        var history: [UUID: [CustomWidgetDisplay.Sample]]?
    }

    init(file: URL?, vault: SecretVault = .keychain) {
        self.file = file
        self.vault = vault
        guard let file, let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        definitions = saved.definitions
        history = saved.history ?? [:]
        let repaired = definitions.indices.map { CustomTimerRepair.repair(&definitions[$0]) }
        if repaired.contains(true) { persist() }
    }

    func definition(_ id: UUID) -> CustomWidgetDefinition? {
        definitions.first { $0.id == id }
    }

    func save(_ definition: CustomWidgetDefinition) {
        var definition = definition
        definition.interval = definition.clampedInterval
        if let index = definitions.firstIndex(where: { $0.id == definition.id }) {
            let previous = definitions[index]
            for old in previous.secretOrigins.subtracting(definition.secretOrigins) {
                vault.delete(Self.secretKey(id: definition.id, origin: old))
            }
            if previous.endpoint != definition.endpoint || previous.selection != definition.selection || previous.origin != definition.origin || previous.script != definition.script {
                history[definition.id] = nil
            }
            definitions[index] = definition
        } else {
            definitions.append(definition)
        }
        fetchedAt[definition.id] = nil
        displays[definition.id] = nil
        revision += 1
        persist()
    }

    func delete(_ id: UUID) {
        guard let definition = definition(id) else { return }
        for origin in definition.secretOrigins { vault.delete(Self.secretKey(id: id, origin: origin)) }
        definitions.removeAll { $0.id == id }
        displays[id] = nil
        history[id] = nil
        fetchedAt[id] = nil
        lastResults[id] = nil
        revision += 1
        persist()
    }

    func confirm(_ id: UUID) {
        guard var definition = definition(id) else { return }
        definition.confirmAll()
        save(definition)
    }

    func secret(for definition: CustomWidgetDefinition) -> CustomSecret? {
        definition.origin.flatMap { secret(id: definition.id, origin: $0) }
    }

    func secret(for definition: CustomWidgetDefinition, origin: String) -> CustomSecret? {
        secret(id: definition.id, origin: origin)
    }

    func setSecret(_ secret: CustomSecret?, for definition: CustomWidgetDefinition) {
        guard let origin = definition.origin else { return }
        setSecret(secret, for: definition, origin: origin)
    }

    func setSecret(_ secret: CustomSecret?, for definition: CustomWidgetDefinition, origin: String) {
        let key = Self.secretKey(id: definition.id, origin: origin)
        if let secret, !secret.value.isEmpty, let data = try? JSONEncoder().encode(secret) {
            vault.write(data, key)
        } else {
            vault.delete(key)
        }
        fetchedAt[definition.id] = nil
        revision += 1
    }

    func hasSecret(_ definition: CustomWidgetDefinition) -> Bool {
        missingSecrets(definition).isEmpty
    }

    func missingSecrets(_ definition: CustomWidgetDefinition) -> [String] {
        guard definition.isScripted else {
            return definition.needsSecret && (secret(for: definition)?.value.isEmpty ?? true) ? [definition.origin ?? definition.baseURL] : []
        }
        return definition.scriptHosts.filter(\.needsSecret).compactMap(\.origin).filter { secret(id: definition.id, origin: $0)?.value.isEmpty ?? true }
    }

    func request(for definition: CustomWidgetDefinition, typed: CustomSecret? = nil, now: Date = .now) throws(CustomRequestError) -> URLRequest {
        guard definition.isConfirmed else { throw .unconfirmed }
        return try CustomRequest.build(definition, now: now) { origin in
            guard let typed, !typed.value.isEmpty, origin == definition.origin else { return secret(id: definition.id, origin: origin) }
            return typed
        }
    }

    func runScript(_ definition: CustomWidgetDefinition, typed: [String: CustomSecret] = [:], now: Date = .now, last: Any? = nil) async -> CustomScriptRunner.Run {
        guard definition.isConfirmed else { return CustomScriptRunner.Run(result: .failure(.unconfirmed), logs: []) }
        do {
            try CustomRequest.validate(definition)
        } catch {
            return CustomScriptRunner.Run(result: .failure(error), logs: [])
        }
        return await CustomScriptRunner.run(definition, now: now, last: last, secret: { origin in
            guard let entered = typed[origin], !entered.value.isEmpty else { return self.secret(id: definition.id, origin: origin) }
            return entered
        }, fetch: fetch)
    }

    func test(_ definition: CustomWidgetDefinition, typed: CustomSecret? = nil, typedHosts: [String: CustomSecret] = [:], now: Date = .now) async -> Result<CustomFetcher.Response, CustomRequestError> {
        if definition.isScripted {
            return await runScript(definition, typed: typedHosts, now: now).result.map { json in
                CustomFetcher.Response(json: json, data: (try? JSONSerialization.data(withJSONObject: json, options: .fragmentsAllowed)) ?? Data())
            }
        }
        do {
            return .success(try await fetch(try request(for: definition, typed: typed, now: now)))
        } catch {
            return .failure(error)
        }
    }

    @discardableResult
    func refresh(_ id: UUID, now: Date = .now) async -> CustomWidgetDisplay? {
        guard let definition = definition(id), !inFlight.contains(id) else { return displays[id] }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        fetchedAt[id] = now
        let display: CustomWidgetDisplay
        switch await test(definition, now: now) {
        case .success(let response):
            lastResults[id] = response.json
            var evaluated = CustomEvaluator.display(for: definition, json: response.json, at: now)
            if let value = CustomEvaluator.selectedValue(definition.selection, in: response.json).flatMap(JSONPath.number) {
                record(value, for: id, at: now)
            }
            if definition.display.style == .line || [definition.display.layout, definition.display.compact, definition.display.wide].contains(where: { $0?.contains(.line) == true }) { evaluated.history = history[id] ?? [] }
            display = evaluated
        case .failure(let error):
            var failed = displays[id] ?? CustomEvaluator.empty(definition)
            failed.error = error.message
            display = failed
        }
        guard self.definition(id) == definition else { return display }
        if displays[id] != display { revision += 1 }
        displays[id] = display
        return display
    }

    func runAction(_ id: UUID, named name: String) async -> (run: CustomScriptRunner.Run, display: CustomWidgetDisplay?) {
        func failed(_ error: CustomRequestError) -> (run: CustomScriptRunner.Run, display: CustomWidgetDisplay?) { (CustomScriptRunner.Run(result: .failure(error), logs: []), nil) }
        guard var definition = definition(id), let action = definition.action(named: name) else { return failed(.unknownAction(name)) }
        guard definition.runnableActionNames.contains(name) else { return failed(.actionNotAllowed(name)) }
        guard actionsInFlight.insert(id).inserted else { return failed(.actionBusy) }
        defer { actionsInFlight.remove(id) }
        definition.script = action.script
        let run = await runScript(definition, last: lastResults[id])
        while inFlight.contains(id) { try? await Task.sleep(for: .milliseconds(100)) }
        return (run, await refresh(id))
    }

    func refreshDue(now: Date = .now) async {
        let due = definitions.filter { definition in
            guard let last = fetchedAt[definition.id] else { return true }
            return now.timeIntervalSince(last) >= Double(definition.clampedInterval)
        }
        await withTaskGroup(of: Void.self) { group in
            for definition in due {
                group.addTask { await self.refresh(definition.id, now: now) }
            }
        }
    }

    func run() async {
        while !Task.isCancelled {
            await refreshDue()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    func feed(only id: UUID? = nil) -> CustomWidgetFeed {
        let widgets = definitions
            .filter { id == nil || $0.id == id }
            .map { definition in
                guard definition.isConfirmed else { return CustomEvaluator.empty(definition, error: CustomRequestError.unconfirmed.message) }
                if !hasSecret(definition) { return CustomEvaluator.empty(definition, error: CustomRequestError.missingSecret.message) }
                return displays[definition.id] ?? CustomEvaluator.empty(definition)
            }
        return CustomWidgetFeed(widgets: widgets)
    }

    func feedJSON(only id: UUID? = nil) -> JSON {
        guard let data = try? JSONEncoder().encode(feed(only: id)),
              let json = try? JSONSerialization.jsonObject(with: data) as? JSON else { return ["widgets": [JSON]()] }
        return json
    }

    private func secret(id: UUID, origin: String) -> CustomSecret? {
        vault.read(Self.secretKey(id: id, origin: origin)).flatMap { try? JSONDecoder().decode(CustomSecret.self, from: $0) }
    }

    private func record(_ value: Double, for id: UUID, at date: Date) {
        history[id] = Array(((history[id] ?? []) + [CustomWidgetDisplay.Sample(at: date, value: value)]).suffix(Self.historyLimit))
        persist()
    }

    private func persist() {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Saved(definitions: definitions, history: history)).write(to: file, options: .atomic)
    }
}
