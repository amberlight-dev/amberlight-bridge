import EventKit
import SwiftUI

struct CalendarSettingsSection: View {
    @Binding var names: [String]?

    var body: some View {
        Section {
            #if os(iOS)
            let available = Self.availableTitles()
            if available.isEmpty {
                nameField
            } else {
                ForEach(available, id: \.self) { title in
                    Toggle(title, isOn: Binding(
                        get: { names?.contains(title) ?? true },
                        set: { isOn in toggle(title, isOn: isOn, available: available) }
                    ))
                }
            }
            #else
            nameField
            #endif
        } header: {
            Text("Kalender")
        } footer: {
            Text("Ohne Auswahl zeigt das Widget alle Kalender.")
        }
    }

    private var nameField: some View {
        TextField("Nur Kalender", text: Binding(
            get: { names?.joined(separator: ", ") ?? "" },
            set: { text in
                let parsed = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                names = parsed.isEmpty ? nil : parsed
            }
        ), prompt: Text("alle, sonst Namen mit Komma"))
    }

    private func toggle(_ title: String, isOn: Bool, available: [String]) {
        var chosen = Set(names ?? available)
        if isOn { chosen.insert(title) } else { chosen.remove(title) }
        names = chosen.count == available.count ? nil : available.filter(chosen.contains)
    }

    #if os(iOS)
    private static func availableTitles() -> [String] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        return Array(Set(EKEventStore().calendars(for: .event).map(\.title))).sorted()
    }
    #endif
}
