import Foundation

enum CustomLayoutPresets {
    struct Preset: Identifiable {
        let id: String
        let title: String
        let layout: CustomNode
        var compact: CustomNode?
        var wide: CustomNode?
        var requires: [String] = []

        func apply(to display: inout CustomWidgetDefinition.Display) {
            display.layout = layout
            display.compact = compact
            display.wide = wide
        }

        func isApplied(in display: CustomWidgetDefinition.Display) -> Bool {
            display.layout == layout && display.compact == compact && display.wide == wide
        }
    }

    static let all = [bigNumber, ringValue, statusHero, mocoToday, mocoTimer]

    static let bigNumber = Preset(id: "big-number", title: String(localized: "Große Zahl mit Verlauf"), layout: decode("""
    {"type":"vstack","spacing":2,"children":[
      {"type":"text","text":"{caption}","size":"xs"},
      {"type":"text","text":"{value}","size":"xl","priority":2},
      {"type":"line"}
    ]}
    """))

    static let ringValue = Preset(id: "ring-value", title: String(localized: "Ring um den Wert (0–100)"), layout: decode("""
    {"type":"ring","value":"value","max":"100","tone":"blue","children":[
      {"type":"text","text":"{value}","size":"m"}
    ]}
    """))

    static let statusHero = Preset(id: "status-hero", title: String(localized: "Status mit Puls"), layout: decode("""
    {"type":"hstack","spacing":10,"children":[
      {"type":"dot","pulse":true,"priority":1},
      {"type":"vstack","spacing":2,"children":[
        {"type":"text","text":"{value}","size":"l","priority":2},
        {"type":"text","text":"{caption}","size":"xs"}
      ]}
    ]}
    """))

    static let mocoToday = Preset(id: "moco-today", title: String(localized: "MOCO: Heute als Ring"), layout: decode("""
    {"type":"hstack","spacing":14,"children":[
      {"type":"ring","value":"booked","max":"8","tone":"blue","priority":2,"children":[
        {"type":"text","text":"{booked}","size":"m"}
      ]},
      {"type":"vstack","spacing":2,"children":[
        {"type":"text","text":"Heute","size":"xs"},
        {"type":"text","text":"{booked} h","size":"l","priority":1},
        {"type":"text","text":"von 8 h Tagessoll","size":"s"}
      ]}
    ]}
    """), requires: ["booked"])

    static let mocoTimer = Preset(id: "moco-timer", title: String(localized: "MOCO: Laufender Timer mit Projekt und Aufgabe"), layout: decode("""
    {"type":"vstack","spacing":4,"children":[
      {"type":"hstack","spacing":4,"children":[
        {"type":"dot","pulse":true,"tone":"green","when":"running >= 1"},
        {"type":"text","text":"{task}","size":"xs","when":"running >= 1"},
        {"type":"text","text":"Kein Timer","size":"xs","when":"running < 1"}
      ]},
      {"type":"text","text":"{project}","size":"m"},
      {"type":"text","text":"{description}","size":"s"},
      {"type":"spacer"},
      {"type":"timer","since":"runningStart","plus":"runningSeconds","plusUnit":"seconds","size":"xl","when":"running >= 1"},
      {"type":"text","text":"{booked} h","size":"xl","when":"running < 1"},
      {"type":"bar","value":"booked","max":"8","tone":"blue","toneWhen":[{"when":"running >= 1","tone":"green"}]},
      {"type":"text","text":"{booked} von 8 h heute","size":"xs"}
    ]}
    """), compact: decode("""
    {"type":"ring","value":"booked","max":"8","tone":"blue","toneWhen":[{"when":"running >= 1","tone":"green"}],"children":[
      {"type":"timer","since":"runningStart","plus":"runningSeconds","plusUnit":"seconds","size":"s","when":"running >= 1"},
      {"type":"text","text":"{booked}","size":"m","when":"running < 1"}
    ]}
    """), wide: decode("""
    {"type":"hstack","spacing":14,"children":[
      {"type":"ring","value":"booked","max":"8","tone":"blue","toneWhen":[{"when":"running >= 1","tone":"green"}],"children":[
        {"type":"text","text":"{booked}","size":"m"}
      ]},
      {"type":"vstack","spacing":3,"children":[
        {"type":"hstack","spacing":4,"children":[
          {"type":"dot","pulse":true,"tone":"green","when":"running >= 1"},
          {"type":"text","text":"{task}","size":"xs","when":"running >= 1"},
          {"type":"text","text":"Kein Timer","size":"xs","when":"running < 1"}
        ]},
        {"type":"text","text":"{project}","size":"m"}
      ]}
    ]}
    """), requires: ["project", "task", "description", "booked", "running", "runningStart", "runningSeconds"])

    private static func decode(_ json: String) -> CustomNode {
        guard let node = try? JSONDecoder().decode(CustomNode.self, from: Data(json.utf8)) else {
            preconditionFailure("Ungültiges Layout-Preset")
        }
        return node
    }
}
