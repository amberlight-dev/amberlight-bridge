import Foundation

extension StandWidget {
    var defaultSpan: GridSpan {
        switch self {
        case .clock: GridSpan(w: 2, h: 2)
        case .claude: GridSpan(w: 3, h: 4)
        case .usage: GridSpan(w: 2, h: 2)
        case .mascot: GridSpan(w: 2, h: 1)
        case .nowPlaying: GridSpan(w: 3, h: 2)
        case .shortcuts: GridSpan(w: 3, h: 2)
        case .mac: GridSpan(w: 2, h: 1)
        case .calendar: GridSpan(w: 2, h: 2)
        case .weather: GridSpan(w: 3, h: 2)
        case .focus: GridSpan(w: 2, h: 1)
        case .orbit: GridSpan(w: 3, h: 2)
        case .gitlab: GridSpan(w: 3, h: 2)
        case .custom: GridSpan(w: 2, h: 2)
        }
    }

    var blurb: String {
        switch self {
        case .clock: String(localized: "Uhrzeit und Datum, groß und von Weitem lesbar.")
        case .claude: String(localized: "Deine Claude- und Codex-Sessions mit Status, Fragen und Freigaben.")
        case .usage: String(localized: "Wie viel deine KI-Abos verbraucht haben – Claude und Codex.")
        case .mascot: String(localized: "Läuft mit, solange deine Sessions arbeiten.")
        case .nowPlaying: String(localized: "Was gerade läuft, mit Play, Pause und Skip.")
        case .shortcuts: String(localized: "Apps, Links und Ordner auf dem Mac mit einem Tipp öffnen.")
        case .mac: String(localized: "CPU, RAM und Netz deines Macs.")
        case .calendar: String(localized: "Deine nächsten Termine heute und morgen.")
        case .weather: String(localized: "Temperatur jetzt und für die nächsten Stunden.")
        case .focus: String(localized: "Ein Pomodoro-Timer: Tippen startet, lange drücken setzt zurück.")
        case .orbit: String(localized: "Deine offenen Orbit-Tickets, ein Tipp öffnet sie am Mac.")
        case .gitlab: String(localized: "Pipelines und offene Merge Requests deiner Projekte.")
        case .custom: String(localized: "Daten aus einer eigenen API, eingerichtet in der Widget-Bibliothek am Mac.")
        }
    }

    var placementSpans: [GridSpan] {
        let top = defaultSpan
        let spans = (minSpan.h...top.h).flatMap { h in (minSpan.w...top.w).map { w in GridSpan(w: w, h: h) } }
        return spans.sorted { ($0.w * $0.h, $0.w) > ($1.w * $1.h, $1.w) }
    }
}

extension PlacedWidget {
    var title: String { widget == .custom ? settings?.customName ?? widget.title : widget.title }
}

extension StandPage {
    mutating func add(_ widget: StandWidget, preferring span: GridSpan? = nil, settings: WidgetSettings? = nil) -> Bool {
        for span in [span].compactMap(\.self) + widget.placementSpans {
            guard let slot = StandGrid.firstFreeSlot(for: span, in: items) else { continue }
            items.append(PlacedWidget(widget: widget, frame: slot, settings: settings))
            return true
        }
        return false
    }

    func sizeOptions(for item: PlacedWidget) -> [GridSpan] {
        var spans: [GridSpan] = []
        for span in item.widget.galleryPresets + [item.frame.span] where !spans.contains(span) {
            spans.append(span)
        }
        return spans
            .filter { span in
                span == item.frame.span
                    || StandGrid.resize(item.id, to: span, in: items)?.first { $0.id == item.id }?.frame.span == span
            }
            .sorted { ($0.w * $0.h, $0.w) < ($1.w * $1.h, $1.w) }
    }
}

extension [StandPage] {
    mutating func add(_ widget: StandWidget, onto pageID: StandPage.ID, preferring span: GridSpan? = nil, settings: WidgetSettings? = nil) -> StandPage.ID {
        let index = firstIndex { $0.id == pageID }
        if let index, self[index].add(widget, preferring: span, settings: settings) { return pageID }
        let page = StandPage(name: settings?.customName ?? widget.title, items: [
            PlacedWidget(widget: widget, frame: GridRect(x: 0, y: 0, span: span ?? widget.defaultSpan), settings: settings),
        ], icon: widget.symbol)
        insert(page, at: index.map { $0 + 1 } ?? endIndex)
        return page.id
    }

    mutating func duplicate(_ item: PlacedWidget, onto pageID: StandPage.ID) -> StandPage.ID {
        add(item.widget, onto: pageID, preferring: item.frame.span, settings: item.settings)
    }
}
