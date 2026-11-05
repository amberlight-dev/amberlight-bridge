import XCTest
@testable import StandBridge

@MainActor
final class CustomEngineTests: XCTestCase {
    func testRowTemplateFillsFallsBackAndFormats() {
        let element: [String: Any] = ["dep": ["dTimeS": "155000", "dTimeR": "155300", "dPltfS": ["txt": "1"]], "name": "rex 1"]
        XCTAssertEqual(CustomRowTemplate.fill("{dep.dTimeR??dep.dTimeS|time} · Gl. {dep.dPltfR.txt??dep.dPltfS.txt}", element), "15:53 · Gl. 1")
        XCTAssertEqual(CustomRowTemplate.fill("{name|upper}", element), "REX 1")
        XCTAssertNil(CustomRowTemplate.fill("{missing}", element))
    }

    func testClockReadsHafasAndISOTimes() {
        XCTAssertEqual(CustomRowTemplate.clock("093200"), "09:32")
        XCTAssertEqual(CustomRowTemplate.clock("1003000"), "00:30")
        XCTAssertEqual(CustomRowTemplate.clock("0930"), "09:30")
        XCTAssertEqual(CustomRowTemplate.clock("pünktlich"), "pünktlich")
    }

    func testVariablesAreSubstitutedAndEscapedInBodies() {
        let variables = [CustomWidgetDefinition.Pair(name: "from", value: #"Wels "Hbf""#)]
        XCTAssertEqual(CustomRequest.substitute("A=1@O={from}@", now: .now, variables: variables), #"A=1@O=Wels "Hbf"@"#)
        XCTAssertEqual(CustomRequest.substitute(#"{"lid":"{from}"}"#, now: .now, variables: variables, escapingJSON: true), #"{"lid":"Wels \"Hbf\""}"#)
    }

    func testTargetGivesProgressAndOverflowForAnyStyle() {
        var definition = CustomWidgetDefinition()
        definition.selection = .init(valuePath: "hours")
        definition.display = .init(style: .text, target: 40)
        let regular = CustomEvaluator.display(for: definition, json: ["hours": 30])
        XCTAssertEqual(regular.progress, 0.75)
        XCTAssertNil(regular.overflow)
        let over = CustomEvaluator.display(for: definition, json: ["hours": 50])
        XCTAssertEqual(over.progress, 1)
        XCTAssertEqual(over.overflow, 0.25)
    }

    func testOebbTemplateBuildsPostAndRendersRows() throws {
        let definition = CustomTemplate.oebbTrips.instantiate()
        let request = try CustomRequest.build(definition) { _ in nil }
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let call = try XCTUnwrap((body["svcReqL"] as? [[String: Any]])?.first)
        XCTAssertEqual(call["meth"] as? String, "TripSearch")
        let json = try XCTUnwrap(CustomTemplate.oebbTrips.sampleJSON())
        let display = CustomEvaluator.display(for: definition, json: json)
        XCTAssertEqual(display.text, "15:51")
        XCTAssertEqual(display.points.first?.label, "15:51")
        XCTAssertEqual(display.points.first?.text, "→ 16:04 · Gl. 1 · 1 Minuten später")
    }

    func testEdgeConfigKeepsCustomSlotsOnlyForCustomWidgets() throws {
        let id = UUID()
        var edges = EdgeConfig.standard
        edges.place(.custom, custom: id, in: .topLeading)
        edges.place(.battery, in: .topTrailing)
        let decoded = try XCTUnwrap(EdgeConfig(rawValue: edges.rawValue))
        XCTAssertEqual(decoded.customs, [.topLeading: id])
        edges.place(.battery, in: .topLeading)
        XCTAssertTrue(edges.customs.isEmpty)
    }
}
