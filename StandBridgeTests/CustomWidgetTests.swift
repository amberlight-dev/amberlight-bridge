import XCTest
@testable import StandBridge

nonisolated final class CustomStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var headers: [String: String] = [:]
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: Self.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class CustomWidgetTests: XCTestCase {
    private let sample: Any = try! JSONSerialization.jsonObject(with: Data("""
    {"data": {"items": [
        {"date": "2026-10-19", "hours": 2.5, "timer_started_at": null, "project": {"name": "Stand"}},
        {"date": "2026-10-19", "hours": 1, "timer_started_at": "", "project": {"name": "Orbit"}},
        {"date": "2026-10-20", "hours": "3.25", "timer_started_at": "2026-10-20T08:00:00Z", "project": {"name": "Stand"}}
    ], "total": 6.75, "odd.key": {"x": true}}}
    """.utf8))

    private func definition(_ base: String = "https://api.example.com/v1", auth: CustomWidgetDefinition.AuthKind = .none) -> CustomWidgetDefinition {
        var definition = CustomWidgetDefinition()
        definition.name = "Test"
        definition.baseURL = base
        definition.auth.kind = auth
        definition.endpoint.path = "stats"
        definition.confirmedOrigin = definition.origin
        return definition
    }

    func testPathParsingAndResolving() {
        XCTAssertEqual(JSONPath.parse("data.items[0].hours"), [.key("data"), .key("items"), .index(0), .key("hours")])
        XCTAssertEqual(JSONPath.parse(""), [])
        XCTAssertEqual(JSONPath.parse("[2]"), [.index(2)])
        XCTAssertEqual(JSONPath.parse("data[\"odd.key\"].x"), [.key("data"), .key("odd.key"), .key("x")])
        XCTAssertNil(JSONPath.parse("data..items"))
        XCTAssertNil(JSONPath.parse("items[-1]"))
        XCTAssertNil(JSONPath.parse("items[abc]"))
        XCTAssertNil(JSONPath.parse(String(repeating: "a.", count: 400)))

        XCTAssertEqual(JSONPath.number(JSONPath.resolve("data.items[0].hours", in: sample)), 2.5)
        XCTAssertEqual(JSONPath.text(JSONPath.resolve("data.items[2].project.name", in: sample)), "Stand")
        XCTAssertEqual(JSONPath.text(JSONPath.resolve("data[\"odd.key\"].x", in: sample)), "true")
        XCTAssertNil(JSONPath.resolve("data.items[9].hours", in: sample))
        XCTAssertNil(JSONPath.resolve("data.total.deeper", in: sample))
    }

    func testClickedPathsRoundTripAndSplit() {
        let path = JSONPath.appending(.key("hours"), to: JSONPath.appending(.index(0), to: JSONPath.appending(.key("items"), to: "data")))
        XCTAssertEqual(path, "data.items[0].hours")
        XCTAssertEqual(JSONPath.appending(.key("odd.key"), to: "data"), "data[\"odd.key\"]")
        XCTAssertEqual(JSONPath.parse(JSONPath.appending(.key("a\"b"), to: "")), [.key("a\"b")])
        let split = JSONPath.elementSplit("data.items[2].project.name")
        XCTAssertEqual(split?.array, "data.items")
        XCTAssertEqual(split?.field, "project.name")
        XCTAssertEqual(JSONPath.elementSplit("[0].hours")?.array, "")
        XCTAssertNil(JSONPath.elementSplit("data.total"))
    }

    func testFilterSelectsElementsBeforeAggregation() {
        func first(_ filter: String?, field: String) -> Any? {
            CustomEvaluator.selectedValue(.init(arrayPath: "data.items", valueField: field, aggregation: .first, filter: filter), in: sample)
        }
        XCTAssertEqual(JSONPath.text(first("timer_started_at", field: "project.name")), "Stand")
        XCTAssertEqual(JSONPath.text(first("project.name == orbit", field: "date")), "2026-10-19")
        XCTAssertEqual(JSONPath.text(first("project.name != Stand", field: "project.name")), "Orbit")
        XCTAssertEqual(JSONPath.number(CustomEvaluator.selectedValue(.init(arrayPath: "data.items", valueField: "hours", aggregation: .sum, filter: "project.name == Stand"), in: sample)), 5.75)
    }

    func testLinesFillTemplatesAndDropMissingValues() {
        var definition = definition()
        definition.values = [
            .init(name: "project", selection: .init(arrayPath: "data.items", valueField: "project.name", aggregation: .first, filter: "timer_started_at")),
            .init(name: "booked", selection: .init(arrayPath: "data.items", valueField: "hours", aggregation: .sum)),
            .init(name: "none", selection: .init(arrayPath: "data.items", valueField: "hours", aggregation: .first, filter: "project.name == Nope")),
        ]
        definition.display.format = .hoursMinutes
        definition.display.lines = ["{project}", "{booked} h heute", "{none}"]
        XCTAssertEqual(CustomEvaluator.lines(for: definition, json: sample), ["Stand", "6:45 h heute"])
        definition.display.lines = nil
        XCTAssertNil(CustomEvaluator.lines(for: definition, json: sample))
    }

    private let mocoDay: Any = try! JSONSerialization.jsonObject(with: Data("""
    [{"hours": 2.5, "timer_started_at": null, "project": {"name": "Orbit"}},
     {"hours": 1.25, "timer_started_at": "2026-10-20T08:00:00+02:00", "project": {"name": "Stand"}}]
    """.utf8))

    func testMocoTimerLayoutResolvesRunningState() throws {
        var definition = CustomTemplate.mocoTimer.instantiate()
        definition.confirmedOrigin = definition.origin
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = try XCTUnwrap(CustomEvaluator.display(for: definition, json: mocoDay, at: now).root)
        XCTAssertEqual(root.children?.map(\.type), [.ring, .hstack, .vstack])
        let ring = try XCTUnwrap(root.children?.first)
        XCTAssertEqual(ring.maxW, 1)
        XCTAssertEqual(ring.progress ?? 0, 3.75 / 8, accuracy: 0.0001)
        XCTAssertEqual(ring.tone, .green)
        XCTAssertEqual(ring.children?.map(\.type), [.timer])
        XCTAssertEqual(ring.children?.first?.start, CustomLayout.date("2026-10-20T08:00:00+02:00"))
        XCTAssertEqual(root.children?[1].children?.first?.children?.first?.text, "3:45")
        let details = try XCTUnwrap(root.children?.last?.children)
        XCTAssertEqual(details.map(\.type), [.hstack, .text, .spacer, .timer, .bar, .text])
        XCTAssertEqual(details[1].text, "Stand")
        XCTAssertEqual(details[3].start, CustomLayout.date("2026-10-20T08:00:00+02:00"))
        XCTAssertEqual(details[4].progress ?? 0, 3.75 / 8, accuracy: 0.0001)
        XCTAssertEqual(details[5].text, "3:45 von 8 h heute")
    }

    func testMocoTimerShowsProjectTaskDescriptionAndElapsed() throws {
        var definition = CustomTemplate.mocoTimer.instantiate()
        definition.confirmedOrigin = definition.origin
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let json = try XCTUnwrap(CustomTemplate.mocoTimer.sampleJSON(now: now))
        let details = try XCTUnwrap(CustomEvaluator.display(for: definition, json: json, at: now).root?.children?.last?.children)
        XCTAssertEqual(details.map(\.type), [.hstack, .text, .text, .spacer, .timer, .bar, .text])
        XCTAssertEqual(details[0].children?.compactMap(\.text), ["Entwicklung"])
        XCTAssertEqual(details[1].text, "Stand-Widgets")
        XCTAssertEqual(details[2].text, "Widget-Editor")
        XCTAssertEqual(details[4].start, now.addingTimeInterval(-25 * 60 - 600))
    }

    func testMocoTimerLayoutHidesRunningPartsWithoutTimer() throws {
        var definition = CustomTemplate.mocoTimer.instantiate()
        definition.confirmedOrigin = definition.origin
        let idle = try JSONSerialization.jsonObject(with: Data(#"[{"hours": 2, "timer_started_at": null, "project": {"name": "Orbit"}}]"#.utf8))
        let root = try XCTUnwrap(CustomEvaluator.display(for: definition, json: idle).root)
        XCTAssertEqual(root.children?.first?.tone, .blue)
        XCTAssertEqual(root.children?.first?.children?.map(\.text), ["2:00"])
        let details = try XCTUnwrap(root.children?.last?.children)
        XCTAssertEqual(details.map(\.type), [.hstack, .spacer, .text, .bar, .text])
        XCTAssertEqual(details[0].children?.map(\.text), ["Kein Timer"])
        XCTAssertEqual(details[2].text, "2:00 h")
        XCTAssertEqual(details[3].tone, .blue)
    }

    func testConditionsAndDates() {
        var scope = CustomLayout.Scope()
        scope.raw = ["a": 2.0, "name": "Stand", "empty": ""]
        XCTAssertTrue(CustomLayout.holds("a >= 2", scope))
        XCTAssertFalse(CustomLayout.holds("a < 2", scope))
        XCTAssertTrue(CustomLayout.holds("name == stand", scope))
        XCTAssertTrue(CustomLayout.holds("!empty", scope))
        XCTAssertFalse(CustomLayout.holds("missing", scope))
        XCTAssertNotNil(CustomLayout.date("2026-10-20T08:00:00Z"))
        XCTAssertNotNil(CustomLayout.date("2026-10-20T08:00:00.123Z"))
        XCTAssertNotNil(CustomLayout.date("2026-10-20T10:00:00+02:00"))
        XCTAssertNil(CustomLayout.date("gestern"))
    }

    func testPresetsDecodeAndStayWithinLimits() throws {
        for preset in CustomLayoutPresets.all {
            XCTAssertFalse(preset.layout.isTooComplex, preset.title)
            let data = try JSONEncoder().encode(preset.layout)
            XCTAssertEqual(try JSONDecoder().decode(CustomNode.self, from: data), preset.layout)
        }
        var definition = definition()
        var node = CustomNode(type: .text, text: "x")
        for _ in 0..<CustomNode.maxDepth { node = CustomNode(type: .vstack, children: [node]) }
        definition.display.layout = node
        XCTAssertThrowsError(try CustomRequest.validate(definition))
    }

    func testClickBindingAddsValueAndLayoutLine() {
        var definition = definition()
        let first = CustomBindings.add(path: "data.items[0].hours", json: sample, to: &definition)
        let second = CustomBindings.add(path: "data.items[0].hours", json: sample, to: &definition)
        let project = CustomBindings.add(path: "data.items[0].project.name", json: sample, to: &definition)
        XCTAssertEqual([first, second, project], ["hours", "hours2", "name"])
        XCTAssertEqual(definition.values?.first?.selection.aggregation, .sum)
        XCTAssertEqual(definition.values?.last?.selection.aggregation, .first)
        XCTAssertEqual(definition.display.layout?.type, .vstack)
        XCTAssertEqual(definition.display.layout?.children?.compactMap(\.text), ["{hours}", "{hours2}", "{name}"])
        let root = CustomEvaluator.display(for: definition, json: sample).root
        XCTAssertEqual(root?.children?.last?.children?.compactMap(\.text), ["7", "7", "Stand"])
    }

    func testClickBindingOnPlainValueUsesPath() {
        var definition = definition()
        CustomBindings.add(path: "data.total", json: sample, to: &definition)
        XCTAssertEqual(definition.values?.first?.selection.valuePath, "data.total")
        XCTAssertNil(definition.values?.first?.selection.arrayPath)
        XCTAssertEqual(CustomBindings.uniqueName(for: "data.value", taken: []), "value2")
        XCTAssertEqual(CustomBindings.uniqueName(for: "", taken: []), "wert")
    }

    func testEveryTemplateRendersItsSample() throws {
        for template in CustomTemplate.all {
            let json = try XCTUnwrap(template.sampleJSON(), template.id)
            let display = CustomEvaluator.display(for: template.definition, json: json)
            XCTAssertNil(display.error, template.id)
            XCTAssertTrue(display.root != nil || display.text != nil || !display.points.isEmpty, template.id)
        }
        let today = try XCTUnwrap(CustomTemplate.mocoToday.sampleJSON())
        let ring = CustomEvaluator.display(for: CustomTemplate.mocoToday.definition, json: today).root?.children?.first
        XCTAssertEqual(ring?.progress ?? 0, 3.92 / 8, accuracy: 0.001)
    }

    func testPresetsOnlyOfferedWhenValuesExist() {
        let names = Set(["booked"])
        let offered = CustomLayoutPresets.all.filter { Set($0.requires).isSubset(of: names) }.map(\.id)
        XCTAssertTrue(offered.contains("moco-today"))
        XCTAssertFalse(offered.contains("moco-timer"))
        XCTAssertTrue(offered.contains("ring-value"))
    }

    func testSmallSizesDeriveFromMostImportantBlocks() throws {
        let main = CustomLayoutPresets.bigNumber.layout
        let compact = try XCTUnwrap(CustomSizing.derived(from: main, for: .compact))
        XCTAssertEqual(compact.text, "{value}")
        let wide = try XCTUnwrap(CustomSizing.derived(from: main, for: .wide))
        XCTAssertEqual(wide.type, .vstack)
        XCTAssertEqual(wide.children?.map(\.text), ["{caption}", "{value}"])
        let hero = try XCTUnwrap(CustomSizing.derived(from: CustomLayoutPresets.statusHero.layout, for: .wide))
        XCTAssertEqual(hero.type, .hstack)
        XCTAssertEqual(hero.children?.map(\.type), [.dot, .text])
        let plain = CustomNode(type: .vstack, children: [CustomNode(type: .spacer), CustomNode(type: .text, text: "a"), CustomNode(type: .divider), CustomNode(type: .text, text: "b")])
        XCTAssertEqual(CustomSizing.derived(from: plain, for: .compact)?.text, "a")
    }

    func testComposedLayoutRoutesSizesAndKeepsLegacyLayouts() throws {
        var display = CustomWidgetDefinition.Display()
        display.layout = CustomLayoutPresets.bigNumber.layout
        let composed = try XCTUnwrap(CustomSizing.composed(display))
        XCTAssertEqual(composed.type, .zstack)
        XCTAssertEqual(composed.children?.map(\.maxW), [1, nil, nil])
        XCTAssertEqual(composed.children?.map(\.minH), [nil, nil, 2])
        display.wide = CustomNode(type: .text, text: "eigene")
        XCTAssertEqual(CustomSizing.composed(display)?.children?[1].text, "eigene")
        var legacy = CustomWidgetDefinition.Display()
        legacy.layout = CustomNode(type: .vstack, children: [CustomNode(type: .text, text: "x", minW: 2)])
        XCTAssertEqual(CustomSizing.composed(legacy), legacy.layout)
    }

    func testEditingInsertMoveBindRemove() throws {
        var display = CustomWidgetDefinition.Display()
        let first = CustomLayoutEditing.insert(CustomBlock.title.node, near: nil, in: &display, tree: .main)
        XCTAssertEqual(first.id, "main:0")
        let ring = CustomLayoutEditing.insert(CustomBlock.ring.node, near: first, in: &display, tree: .main)
        XCTAssertEqual(ring.id, "main:1")
        let row = CustomLayoutEditing.insert(CustomBlock.row.node, near: nil, in: &display, tree: .main)
        let inside = CustomLayoutEditing.insert(CustomBlock.pill.node, near: row, in: &display, tree: .main)
        XCTAssertEqual(inside.id, "main:2.0")
        CustomLayoutEditing.bind("booked", to: ring, in: &display)
        XCTAssertEqual(CustomLayoutEditing.node(at: ring, in: display)?.value, "booked")
        CustomLayoutEditing.bind("project", to: first, in: &display)
        XCTAssertEqual(CustomLayoutEditing.node(at: first, in: display)?.text, "{project}")
        CustomLayoutEditing.bind("task", to: first, in: &display)
        XCTAssertEqual(CustomLayoutEditing.node(at: first, in: display)?.text, "{task}")
        CustomLayoutEditing.update(&display, at: first) { $0.text = "Heute: {task}" }
        CustomLayoutEditing.bind("project", to: first, in: &display)
        XCTAssertEqual(CustomLayoutEditing.node(at: first, in: display)?.text, "Heute: {task} {project}")
        let moved = CustomLayoutEditing.move(at: ring, by: -1, in: &display)
        XCTAssertEqual(moved.id, "main:0")
        XCTAssertEqual(display.layout?.children?.map(\.type), [.ring, .text, .hstack])
        XCTAssertEqual(CustomLayoutEditing.move(at: moved, by: -1, in: &display), moved)
        let next = CustomLayoutEditing.remove(at: moved, in: &display)
        XCTAssertEqual(next?.id, "main:0")
        XCTAssertEqual(display.layout?.children?.map(\.type), [.text, .hstack])
        XCTAssertEqual(CustomLayoutEditing.remove(at: CustomNodeRef(tree: .main, path: [1, 0]), in: &display)?.id, "main:1")
    }

    func testCustomizeCopiesDerivedLayoutAndResetFallsBack() {
        var display = CustomWidgetDefinition.Display()
        CustomLayoutPresets.bigNumber.apply(to: &display)
        CustomLayoutEditing.customize(.compact, in: &display)
        XCTAssertEqual(display.compact?.text, "{value}")
        XCTAssertNil(display.compact?.ref)
        CustomLayoutEditing.insert(CustomBlock.label.node, near: nil, in: &display, tree: .compact)
        XCTAssertEqual(display.compact?.children?.count, 2)
        XCTAssertEqual(display.layout, CustomLayoutPresets.bigNumber.layout)
        CustomLayoutEditing.setRoot(nil, of: &display, tree: .compact)
        XCTAssertEqual(CustomSizing.layout(of: display, for: .compact)?.text, "{value}")
    }

    func testCodeAndBuilderRoundTrip() throws {
        var definition = CustomTemplate.mocoTimer.instantiate()
        CustomLayoutEditing.insert(CustomBlock.pill.node, near: CustomNodeRef(tree: .main, path: [1]), in: &definition.display, tree: .main)
        CustomLayoutEditing.customize(.wide, in: &definition.display)
        CustomLayoutEditing.update(&definition.display, at: CustomNodeRef(tree: .main, path: [2])) { $0.color = "accent"; $0.priority = 2 }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let code = try encoder.encode(definition)
        let decoded = try JSONDecoder().decode(CustomWidgetDefinition.self, from: code)
        XCTAssertEqual(decoded.display.layout, definition.display.layout)
        XCTAssertEqual(decoded.display.compact, definition.display.compact)
        XCTAssertEqual(decoded.display.wide, definition.display.wide)
        XCTAssertEqual(decoded.values?.map(\.name), definition.values?.map(\.name))
        XCTAssertEqual(try encoder.encode(decoded), code)
        XCTAssertNoThrow(try CustomRequest.validate(decoded))
    }

    func testEditingPreviewAnnotatesRefsAndShowsPlaceholders() throws {
        var definition = definition()
        CustomLayoutEditing.insert(CustomNode(type: .text, text: "{fehlt}", size: .m), near: nil, in: &definition.display, tree: .main)
        let root = try XCTUnwrap(CustomEvaluator.display(for: definition, json: sample, editing: true).root)
        let main = try XCTUnwrap(root.children?.last)
        XCTAssertEqual(main.ref, "main:")
        XCTAssertEqual(main.children?.first?.text, "{fehlt}")
        XCTAssertEqual(main.children?.first?.ref, "main:0")
        XCTAssertEqual(root.children?.first?.ref, "main:0")
        XCTAssertNil(CustomEvaluator.display(for: definition, json: sample).root)
        XCTAssertEqual(CustomNodeRef("main:2.0")?.path, [2, 0])
        XCTAssertNil(CustomNodeRef("oops"))
    }

    func testLayoutHistoryUndoRedoAndCoalescing() {
        let history = LayoutHistory()
        var state = definition()
        let start = Date(timeIntervalSince1970: 0)
        history.record(state, key: "name", now: start)
        state.name = "A"
        history.record(state, key: "name", now: start.addingTimeInterval(0.5))
        state.name = "AB"
        XCTAssertEqual(history.past.count, 1)
        let undone = history.undo(state)
        XCTAssertEqual(undone?.name, "Test")
        XCTAssertEqual(history.redo(undone!)?.name, "AB")
    }

    func testTimerAddsAlreadyTrackedTimeToStart() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var scope = CustomLayout.Scope()
        scope.raw = ["start": now.addingTimeInterval(-25 * 60).formatted(.iso8601), "tracked": 3600.0, "hours": 1.5]
        let seconds = CustomNode(type: .timer, since: "start", plus: "tracked", plusUnit: "seconds")
        XCTAssertEqual(CustomLayout.timerStart(seconds, scope), now.addingTimeInterval(-85 * 60))
        let legacy = CustomNode(type: .timer, since: "start", plus: "hours")
        XCTAssertEqual(CustomLayout.timerStart(legacy, scope), now.addingTimeInterval(-115 * 60))
        let minutes = CustomNode(type: .timer, since: "start", plus: "hours", plusUnit: "minutes")
        XCTAssertEqual(CustomLayout.timerStart(minutes, scope), now.addingTimeInterval(-25 * 60 - 90))
        XCTAssertNil(CustomLayout.resolve(CustomNode(type: .timer, since: "fehlt"), scope: scope))
        XCTAssertNil(CustomLayout.resolve(seconds, scope: scope)?.plusUnit)
    }

    func testOldMocoTimerWidgetsAreRepairedWithoutLosingLayout() throws {
        var old = CustomTemplate.mocoTimer.instantiate()
        old.values?.removeAll { ["runningStart", "runningSeconds", "running"].contains($0.name) }
        old.values?.append(.init(name: "runningHours", selection: .init(arrayPath: "", valueField: "hours", aggregation: .sum, filter: "timer_started_at")))
        old.display.layout = CustomNode(type: .vstack, children: [
            CustomNode(type: .text, text: "Mein Titel", size: .l),
            CustomNode(type: .timer, size: .xl, since: "now", plus: "runningHours"),
        ])
        old.display.compact = CustomNode(type: .timer, since: "now", plus: "runningHours")
        old.display.wide = nil
        XCTAssertTrue(CustomTimerRepair.repair(&old))
        XCTAssertEqual(old.display.layout?.children?.first?.text, "Mein Titel")
        let timer = try XCTUnwrap(old.display.layout?.children?.last)
        XCTAssertEqual([timer.since, timer.plus, timer.plusUnit], ["runningStart", "runningSeconds", "seconds"])
        XCTAssertEqual(timer.size, .xl)
        XCTAssertEqual(old.display.compact?.since, "runningStart")
        XCTAssertEqual(Set(old.values?.map(\.name) ?? []).isSuperset(of: ["running", "runningStart", "runningSeconds", "runningHours"]), true)
        XCTAssertFalse(CustomTimerRepair.repair(&old))

        let json = try JSONSerialization.jsonObject(with: Data(#"[{"seconds": 3600, "hours": 1, "timer_started_at": "2026-10-23T08:00:00Z", "project": {"name": "P"}}, {"seconds": 1800, "hours": 0.5, "timer_started_at": null}]"#.utf8))
        let scope = CustomLayout.scope(for: old, json: json, at: .now)
        XCTAssertEqual(CustomLayout.timerStart(timer, scope), CustomLayout.date("2026-10-23T07:00:00Z"))
    }

    func testRepairOnlyTouchesMocoActivityWidgets() {
        var imported = definition("https://lab73.mocoapp.com/api/v1")
        imported.endpoint.path = "activities"
        imported.display.layout = CustomNode(type: .timer, since: "runningHours", plus: "timer_started_at")
        XCTAssertTrue(CustomTimerRepair.repair(&imported))
        XCTAssertEqual(imported.display.layout?.since, "runningStart")

        var other = definition()
        other.display.layout = CustomNode(type: .timer, since: "now")
        XCTAssertFalse(CustomTimerRepair.repair(&other))
        XCTAssertEqual(other.display.layout?.since, "now")

        var custom = CustomTemplate.mocoTimer.instantiate()
        custom.values?.append(.init(name: "start", selection: .init(valuePath: "x")))
        custom.display.layout = CustomNode(type: .timer, since: "start")
        CustomTimerRepair.repair(&custom)
        XCTAssertEqual(custom.display.layout?.since, "start")
        XCTAssertEqual(custom.repairVersion, CustomTimerRepair.version)
    }

    func testHalfRepairedLiveWidgetMovesToFilteredStartAndSeconds() throws {
        var live = definition("https://lab73.mocoapp.com/api/v1")
        live.endpoint.path = "activities"
        live.values = [
            .init(name: "running", selection: .init(arrayPath: "", valueField: "timer_started_at", aggregation: .countPresent)),
            .init(name: "runningHours", selection: .init(arrayPath: "", valueField: "hours", aggregation: .sum, filter: "timer_started_at")),
            .init(name: "timer_started_at", selection: .init(arrayPath: "", valueField: "timer_started_at", aggregation: .first)),
            .init(name: "hours", selection: .init(arrayPath: "", valueField: "hours", aggregation: .sum)),
        ]
        live.display.layout = CustomNode(type: .vstack, children: [
            CustomNode(type: .text, text: "{project}"),
            CustomNode(type: .timer, when: "running >= 1", since: "timer_started_at", plus: "runningHours"),
        ])
        XCTAssertTrue(CustomTimerRepair.repair(&live))
        let timer = try XCTUnwrap(live.display.layout?.children?.last)
        XCTAssertEqual([timer.since, timer.plus, timer.plusUnit, timer.when], ["runningStart", "runningSeconds", "seconds", "running >= 1"])
        XCTAssertEqual(live.display.layout?.children?.first?.text, "{project}")
        XCTAssertEqual(live.values?.first { $0.name == "runningStart" }?.selection.filter, "timer_started_at")
        XCTAssertEqual(live.values?.first { $0.name == "runningSeconds" }?.selection.valueField, "seconds")
        XCTAssertEqual(live.values?.count, 6)

        let json = try JSONSerialization.jsonObject(with: Data(#"[{"seconds": 1800, "hours": 0.5, "timer_started_at": null}, {"seconds": 3600, "hours": 1, "timer_started_at": "2026-10-23T08:00:00Z"}]"#.utf8))
        XCTAssertEqual(CustomLayout.timerStart(timer, CustomLayout.scope(for: live, json: json, at: .now)), CustomLayout.date("2026-10-23T07:00:00Z"))

        XCTAssertFalse(CustomTimerRepair.repair(&live))
        CustomLayoutEditing.update(&live.display, at: CustomNodeRef(tree: .main, path: [1])) { $0.plusUnit = "minutes" }
        XCTAssertFalse(CustomTimerRepair.repair(&live))
        XCTAssertEqual(live.display.layout?.children?.last?.plusUnit, "minutes")
    }

    func testReferencedNamesFromConditions() {
        XCTAssertEqual(CustomLayout.referencedNames(in: "running >= 1"), ["running"])
        XCTAssertEqual(CustomLayout.referencedNames(in: "!project"), ["project"])
        XCTAssertEqual(CustomLayout.referencedNames(in: " "), [])
    }

    func testAggregations() {
        func value(_ aggregation: CustomWidgetDefinition.Aggregation, field: String = "hours") -> Any? {
            CustomEvaluator.selectedValue(.init(arrayPath: "data.items", valueField: field, aggregation: aggregation), in: sample)
        }
        XCTAssertEqual(JSONPath.number(value(.sum)), 6.75)
        XCTAssertEqual(JSONPath.number(value(.count)), 3)
        XCTAssertEqual(JSONPath.number(value(.countPresent, field: "timer_started_at")), 1)
        XCTAssertEqual(JSONPath.number(value(.average)), 2.25)
        XCTAssertEqual(JSONPath.number(value(.minimum)), 1)
        XCTAssertEqual(JSONPath.number(value(.maximum)), 3.25)
        XCTAssertEqual(JSONPath.text(value(.first, field: "project.name")), "Stand")
        XCTAssertEqual(JSONPath.text(value(.last, field: "date")), "2026-10-20")
        XCTAssertNil(value(.average, field: "missing"))
        XCTAssertNil(CustomEvaluator.selectedValue(.init(arrayPath: "data.total", valueField: "hours"), in: sample))
    }

    func testSeriesGroupsLabelsAndFormatsValues() {
        var definition = definition()
        definition.selection = .init(arrayPath: "data.items", valueField: "hours", aggregation: .sum, seriesPath: "data.items",
                                     labelField: "date", seriesField: "hours", groupsLabels: true, labelsAreDates: true)
        definition.display = .init(style: .bar, format: .hoursMinutes, unit: "h")
        let display = CustomEvaluator.display(for: definition, json: sample)
        XCTAssertEqual(display.text, "6:45\u{202F}h")
        XCTAssertEqual(display.points.map(\.value), [3.5, 3.25])
        XCTAssertEqual(display.points.map(\.text), ["3:30\u{202F}h", "3:15\u{202F}h"])
        XCTAssertEqual(display.points.count, 2)
        XCTAssertNil(display.error)

        var decimals = CustomWidgetDefinition.Display()
        decimals.decimals = 1
        decimals.prefix = "≈ "
        decimals.unit = "°C"
        XCTAssertEqual(CustomEvaluator.formatted(12.345, display: decimals), "≈ 12,3\u{202F}°C")
    }

    func testStatusRulesPickFirstMatch() {
        var definition = definition()
        definition.selection = .init(arrayPath: "data.items", valueField: "timer_started_at", aggregation: .countPresent)
        definition.display = .init(style: .status, rules: [
            .init(comparison: .atLeast, operand: "1", tone: .green, label: "Timer läuft"),
            .init(comparison: .below, operand: "1", tone: .gray, label: "Kein Timer"),
        ])
        let running = CustomEvaluator.display(for: definition, json: sample)
        XCTAssertEqual(running.tone, .green)
        XCTAssertEqual(running.text, "Timer läuft")

        definition.selection = .init(valuePath: "data.items[0].project.name")
        definition.display.rules = [.init(comparison: .equals, operand: "stand", tone: .blue, label: "")]
        let matched = CustomEvaluator.display(for: definition, json: sample)
        XCTAssertEqual(matched.tone, .blue)
        XCTAssertEqual(matched.text, "Stand")

        definition.selection = .init(valuePath: "nope")
        XCTAssertEqual(CustomEvaluator.display(for: definition, json: sample).error, "Wert nicht gefunden")
    }

    func testExportNeverContainsSecretsAndImportNeedsNewConfirmation() throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        var original = definition(auth: .customHeader)
        original.auth.name = "Authorization"
        original.auth.prefix = "Token token="
        original.endpoint.headers = [.init(name: "Accept-Language", value: "de"), .init(name: "X-Session-Token", value: "leak-1")]
        original.endpoint.query = [.init(name: "from", value: "{today}"), .init(name: "access_token", value: "leak-2")]
        store.save(original)
        store.setSecret(CustomSecret(value: "super-secret-key", username: "julian"), for: original)
        XCTAssertTrue(store.hasSecret(original))

        let text = CustomWidgetShare.export(original)
        XCTAssertTrue(text.hasPrefix("stand-widget:"))
        let payload = String(decoding: try XCTUnwrap(Data(base64Encoded: base64(text))), as: UTF8.self)
        for secret in ["super-secret-key", "julian", "leak-1", "leak-2", "confirmedOrigin"] {
            XCTAssertFalse(payload.contains(secret), secret)
        }

        let imported = try CustomWidgetShare.decode("  \(text)\n")
        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertNil(imported.confirmedOrigin)
        XCTAssertEqual(imported.endpoint.headers.map(\.name), ["Accept-Language"])
        XCTAssertEqual(imported.auth, original.auth)
        store.save(imported)
        XCTAssertFalse(store.hasSecret(imported))
        XCTAssertThrowsError(try store.request(for: imported)) { XCTAssertEqual($0 as? CustomRequestError, .unconfirmed) }
        XCTAssertEqual(store.feed(only: imported.id).widgets.first?.error, CustomRequestError.unconfirmed.message)
        store.confirm(imported.id)
        XCTAssertThrowsError(try store.request(for: try XCTUnwrap(store.definition(imported.id)))) {
            XCTAssertEqual($0 as? CustomRequestError, .missingSecret)
        }
    }

    func testImportRejectsForeignAndUnsafeText() {
        XCTAssertThrowsError(try CustomWidgetShare.decode("hallo")) { XCTAssertEqual($0 as? CustomWidgetShare.ImportError, .notAWidget) }
        XCTAssertThrowsError(try CustomWidgetShare.decode("stand-widget:@@@")) { XCTAssertEqual($0 as? CustomWidgetShare.ImportError, .unreadable) }
        XCTAssertThrowsError(try CustomWidgetShare.decode("stand-widget:" + String(repeating: "A", count: 70_000))) {
            XCTAssertEqual($0 as? CustomWidgetShare.ImportError, .tooLong)
        }
        var plain = definition("http://example.com")
        XCTAssertThrowsError(try CustomWidgetShare.decode(CustomWidgetShare.export(plain))) {
            XCTAssertEqual($0 as? CustomWidgetShare.ImportError, .invalid(.insecureScheme))
        }
        plain.baseURL = "https://user:pass@example.com"
        XCTAssertThrowsError(try CustomWidgetShare.decode(CustomWidgetShare.export(plain))) {
            XCTAssertEqual($0 as? CustomWidgetShare.ImportError, .invalid(.userInfo))
        }
    }

    func testCredentialsAreBoundToTheirHost() throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        var widget = definition(auth: .bearer)
        store.save(widget)
        store.setSecret(CustomSecret(value: "abc"), for: widget)

        let request = try store.request(for: widget)
        XCTAssertEqual(request.url?.host(), "api.example.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")

        widget.endpoint.path = "//evil.example/steal"
        XCTAssertEqual(try store.request(for: widget).url?.host(), "api.example.com")

        widget.baseURL = "https://evil.example/v1"
        widget.confirmedOrigin = widget.origin
        XCTAssertNil(store.secret(for: widget))
        XCTAssertThrowsError(try store.request(for: widget)) { XCTAssertEqual($0 as? CustomRequestError, .missingSecret) }
        store.save(widget)
        widget.baseURL = "https://api.example.com/v1"
        widget.confirmedOrigin = widget.origin
        XCTAssertNil(store.secret(for: widget), "Host-Wechsel verwirft die alten Zugangsdaten")

        var other = definition("https://api.example.com:8443/v1", auth: .bearer)
        other.id = widget.id
        XCTAssertNil(store.secret(for: other), "anderer Port ist ein anderer Host")
    }

    func testRedirectToAnotherHostIsBlocked() {
        let guardian = RedirectGuard(origin: "https://api.example.com")
        XCTAssertTrue(guardian.allows(URLRequest(url: URL(string: "https://api.example.com/b")!)))
        XCTAssertFalse(guardian.blocked)
        XCTAssertFalse(guardian.allows(URLRequest(url: URL(string: "http://api.example.com/b")!)))
        XCTAssertFalse(guardian.allows(URLRequest(url: URL(string: "https://evil.example/b")!)))
        XCTAssertTrue(guardian.blocked)
    }

    func testSchemePolicyAndSensitiveNames() {
        XCTAssertNoThrow(try CustomRequest.validate(definition("http://192.168.1.20:8080")))
        XCTAssertNoThrow(try CustomRequest.validate(definition("http://localhost:3000")))
        XCTAssertNoThrow(try CustomRequest.validate(definition("http://[::1]:3000")))
        XCTAssertThrowsError(try CustomRequest.validate(definition("http://example.com")))
        XCTAssertThrowsError(try CustomRequest.validate(definition("http://172.32.0.1")))
        XCTAssertThrowsError(try CustomRequest.validate(definition("ftp://example.com")))
        XCTAssertFalse(CustomRequest.isPrivate(host: "fdroid.org"))
        XCTAssertFalse(CustomRequest.isPrivate(host: "10.example.com"))

        var headers = definition()
        headers.endpoint.headers = [.init(name: "Authorization", value: "x")]
        XCTAssertThrowsError(try CustomRequest.validate(headers)) { XCTAssertEqual($0 as? CustomRequestError, .sensitiveName("Authorization")) }
        var query = definition("https://api.example.com/v1?apikey=1")
        XCTAssertThrowsError(try CustomRequest.validate(query))
        query = definition()
        query.endpoint.query = [.init(name: "user_id", value: "")]
        XCTAssertNoThrow(try CustomRequest.validate(query))
        XCTAssertFalse(try CustomRequest.build(query) { _ in nil }.url!.absoluteString.contains("user_id"))
    }

    func testDatePlaceholders() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
        XCTAssertEqual(CustomRequest.substitute("{today}/{weekStart}/{weekEnd}/{monthStart}", now: wednesday), "2026-10-21/2026-10-19/2026-10-25/2026-10-01")
    }

    func testResponseSizeLimit() async throws {
        let session = CustomFetcher.session(protocols: [CustomStubProtocol.self])
        let request = URLRequest(url: URL(string: "https://api.example.com/x")!)
        CustomStubProtocol.headers = ["Content-Type": "application/json"]
        CustomStubProtocol.body = Data("{\"ok\": 1}".utf8)
        let small = try await CustomFetcher.fetch(request, session: session, limit: 64)
        XCTAssertEqual(JSONPath.number(JSONPath.resolve("ok", in: small.json)), 1)

        CustomStubProtocol.body = Data(("[" + String(repeating: "1,", count: 100) + "1]").utf8)
        do {
            _ = try await CustomFetcher.fetch(request, session: session, limit: 64)
            XCTFail("zu groß")
        } catch {
            XCTAssertEqual(error, .tooLarge)
        }

        CustomStubProtocol.body = Data("<html>".utf8)
        do {
            _ = try await CustomFetcher.fetch(request, session: session, limit: 64)
            XCTFail("kein JSON")
        } catch {
            XCTAssertEqual(error, .notJSON)
        }
    }

    func testRefreshBuildsHistoryAndRouteNeedsToken() async throws {
        let store = CustomWidgetStore(file: nil, vault: .memory())
        var widget = definition()
        widget.selection = .init(valuePath: "data.total")
        widget.display = .init(style: .line, decimals: 2)
        store.save(widget)
        var calls = 0
        store.fetch = { _ throws(CustomRequestError) in
            calls += 1
            return CustomFetcher.Response(json: ["data": ["total": calls]], data: Data())
        }
        await store.refresh(widget.id, now: Date(timeIntervalSince1970: 0))
        await store.refresh(widget.id, now: Date(timeIntervalSince1970: 60))
        let display = try XCTUnwrap(store.feed().widgets.first)
        XCTAssertEqual(display.text, "2,00")
        XCTAssertEqual(display.history.map(\.value), [1, 2])

        await store.refreshDue(now: Date(timeIntervalSince1970: 61))
        XCTAssertEqual(calls, 2, "Intervall noch nicht abgelaufen")

        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), token: "abcd1234", port: 1, hostName: "mac.local")
        server.custom = { store.feedJSON(only: $0) }
        func get(_ path: String, token: String) throws -> HTTPRequest {
            try XCTUnwrap(HTTPRequest.parse(Data("GET \(path) HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: 0\r\n\r\n".utf8)))
        }
        let denied = await server.route(try get("/custom", token: "nope"), fromLoopback: false)
        XCTAssertEqual(denied.0, 401)
        let one = await server.route(try get("/custom?id=\(widget.id.uuidString)", token: "abcd1234"), fromLoopback: false)
        XCTAssertEqual((one.1["widgets"] as? [JSON])?.first?["text"] as? String, "2,00")
        let none = await server.route(try get("/custom?id=kaputt", token: "abcd1234"), fromLoopback: false)
        XCTAssertEqual((none.1["widgets"] as? [JSON])?.count, 0)
    }

    private func base64(_ text: String) -> String {
        var base64 = String(text.dropFirst(CustomWidgetShare.prefix.count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return base64
    }
}
