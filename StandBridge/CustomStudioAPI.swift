import AppKit
import SwiftUI

@MainActor
enum CustomStudioAPI {
    static let sizes = [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 2, h: 2), GridSpan(w: 3, h: 2)]

    static func handle(_ request: HTTPRequest, store: CustomWidgetStore) async -> (Int, JSON) {
        switch (request.method, request.path) {
        case ("GET", "/studio/widgets"):
            return (200, ["widgets": store.definitions.compactMap(encoded), "templates": CustomTemplate.all.map(summary)])
        case ("POST", "/studio/widgets"):
            return await save(request.json, store: store)
        case ("DELETE", "/studio/widgets"):
            guard let id = request.query["id"].flatMap(UUID.init(uuidString:)), store.definition(id) != nil else { return (404, [:]) }
            store.delete(id)
            return (200, [:])
        case ("POST", "/studio/render"):
            return await render(request.json, store: store)
        case ("POST", "/studio/run"):
            return await run(request.json, store: store)
        default:
            return (404, [:])
        }
    }

    static func definition(from patch: JSON, base: CustomWidgetDefinition) -> CustomWidgetDefinition? {
        guard let current = encoded(base),
              let data = try? JSONSerialization.data(withJSONObject: merged(current, patch)) else { return nil }
        return try? JSONDecoder().decode(CustomWidgetDefinition.self, from: data)
    }

    static func merged(_ base: JSON, _ patch: JSON) -> JSON {
        patch.reduce(into: base) { result, entry in
            if let nested = entry.value as? JSON, let existing = result[entry.key] as? JSON {
                result[entry.key] = merged(existing, nested)
            } else if entry.value is NSNull {
                result[entry.key] = nil
            } else {
                result[entry.key] = entry.value
            }
        }
    }

    private static func save(_ body: JSON, store: CustomWidgetStore) async -> (Int, JSON) {
        let patch = body["definition"] as? JSON ?? [:]
        let id = (patch["id"] as? String).flatMap(UUID.init(uuidString:))
        let base: CustomWidgetDefinition
        if let id, let existing = store.definition(id) {
            base = existing
        } else if let template = (body["template"] as? String).flatMap(CustomTemplate.named) {
            base = template.instantiate()
        } else {
            base = CustomWidgetDefinition()
        }
        guard var definition = definition(from: patch, base: base) else { return (400, ["error": "Definition passt nicht zum Schema"]) }
        definition.confirmedOrigin = base.confirmedOrigin
        definition.confirmedHosts = base.confirmedHosts
        do {
            try CustomRequest.validate(definition)
        } catch {
            return (400, ["error": error.message])
        }
        store.save(definition)
        CustomApprovalNotice.update(definition, store: store)
        let display = await store.refresh(definition.id)
        return (200, ["definition": encoded(definition) ?? [:], "display": display.flatMap(encoded) ?? NSNull(), "pending": pending(definition, store: store)])
    }

    static func pending(_ definition: CustomWidgetDefinition, store: CustomWidgetStore) -> [String] {
        let place = "Amberlight Bridge → Widget-Bibliothek → „\(definition.name)“ (öffnet direkt: \(CustomApprovalNotice.link(for: definition.id)); die Bridge zeigt dazu auch eine Mitteilung)"
        let writers = Set(definition.unconfirmedHosts.filter(\.writes).compactMap(\.origin))
        let hosts = CustomApprovalNotice.unapprovedOrigins(of: definition).map { writers.contains($0) ? "\($0) (auch schreibend)" : $0 }
        return hosts.map { "Host \($0) muss der Mensch am Mac freigeben: \(place)" }
            + store.missingSecrets(definition).map { "Zugangsdaten für \($0) trägt der Mensch am Mac ein: \(place)" }
    }

    private static func run(_ body: JSON, store: CustomWidgetStore) async -> (Int, JSON) {
        guard let id = (body["id"] as? String).flatMap(UUID.init(uuidString:)), var definition = store.definition(id) else { return (404, ["error": "Widget nicht gefunden"]) }
        if let script = body["script"] as? String { definition.script = script }
        guard definition.isScripted else { return (400, ["error": "Widget hat kein Skript"]) }
        let run = await store.runScript(definition)
        var result: JSON = ["logs": run.logs, "pending": pending(definition, store: store)]
        switch run.result {
        case .success(let output): result["output"] = output
        case .failure(let error): result["error"] = error.message
        }
        return (200, result)
    }

    private static func render(_ body: JSON, store: CustomWidgetStore) async -> (Int, JSON) {
        let id = (body["id"] as? String).flatMap(UUID.init(uuidString:))
        let display: CustomWidgetDisplay?
        if let sample = body["sample"], let patch = body["definition"] as? JSON {
            let base = id.flatMap(store.definition) ?? CustomWidgetDefinition()
            guard let definition = definition(from: patch, base: base) else { return (400, ["error": "Definition passt nicht zum Schema"]) }
            display = CustomEvaluator.display(for: definition, json: sample)
        } else if let id, store.definition(id) != nil {
            await store.refresh(id)
            display = store.feed(only: id).widgets.first
        } else {
            return (404, ["error": "Widget nicht gefunden"])
        }
        let spans = (body["sizes"] as? [String])?.compactMap(span) ?? sizes
        guard let png = png(of: display, spans: spans.isEmpty ? sizes : spans, dimmed: body["dimmed"] as? Bool ?? false) else { return (500, ["error": "Rendern fehlgeschlagen"]) }
        return (200, ["png": png.base64EncodedString(), "display": display.flatMap(encoded) ?? NSNull()])
    }

    static func span(_ text: String) -> GridSpan? {
        let parts = text.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, (1...6).contains(parts[0]), (1...4).contains(parts[1]) else { return nil }
        return GridSpan(w: parts[0], h: parts[1])
    }

    static func png(of display: CustomWidgetDisplay?, spans: [GridSpan], dimmed: Bool) -> Data? {
        let renderer = ImageRenderer(content: StudioSheet(display: display, spans: spans, dimmed: dimmed))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    private static func summary(_ template: CustomTemplate) -> JSON {
        ["id": template.id, "group": template.group, "title": template.title, "blurb": template.blurb, "needsAccount": template.needsAccount]
    }

    private static func encoded(_ value: some Encodable) -> JSON? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? JSON
    }
}

private struct StudioSheet: View {
    let display: CustomWidgetDisplay?
    let spans: [GridSpan]
    let dimmed: Bool

    private static let cell = CGSize(width: 116, height: 69)
    private static let gap: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                VStack(spacing: 8) {
                    CustomWidgetView(display: display, span: span, dimmed: dimmed, notice: String(localized: "Keine Daten"))
                        .frame(width: Self.size(of: span).width, height: Self.size(of: span).height)
                        .clipped()
                    Text("\(span.w)×\(span.h)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(28)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .environment(\.rendersStill, true)
    }

    private static func size(of span: GridSpan) -> CGSize {
        CGSize(width: CGFloat(span.w) * cell.width + CGFloat(span.w - 1) * gap, height: CGFloat(span.h) * cell.height + CGFloat(span.h - 1) * gap)
    }
}
