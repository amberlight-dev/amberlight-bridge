import AppKit
import SwiftUI

struct RepliesView: View {
    let model: BridgeModel
    @AppStorage(MacReply.directReplyKey) private var directReply = false
    @State private var isTrusted = MacReply.isTrusted

    var body: some View {
        Form {
            Section {
                explanation(
                    "Fragen und Erlaubnisse",
                    symbol: "checkmark.bubble",
                    text: "Wartet Claude Code auf deine Antwort oder Erlaubnis, geht dein Tipp am iPhone direkt an die laufende Session. Das klappt immer, ganz ohne Freigabe."
                )
                explanation(
                    "Vorschläge am Ende einer Antwort",
                    symbol: "text.bubble",
                    text: "Ist Claude fertig und bietet Knöpfe wie „Ja, committen“ an, ist deine Wahl eine neue Nachricht. Die muss jemand ins Eingabefeld der Session tippen und abschicken – du am Mac oder die Bridge."
                )
            } header: {
                Text("Zwei Arten von Antworten")
            }

            Section {
                Toggle("Antworten direkt senden", isOn: $directReply)
                if directReply && !isTrusted {
                    LabeledContent {
                        Button("Bedienungshilfen öffnen …") { NSWorkspace.shared.open(MacReply.accessibilitySettings) }
                    } label: {
                        StatusLabel(text: "Bedienungshilfen sind noch nicht freigegeben", symbol: "exclamationmark.triangle.fill", tint: .yellow)
                    }
                }
            } header: {
                Text("Vorschläge vom iPhone")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("**Aus:** Die Bridge legt den Text in die Zwischenablage und holt das Fenster der Session nach vorn. Einfügen und abschicken machst du selbst mit ⌘V und Return.")
                    Text("**An:** Die Bridge drückt ⌘V und Return für dich. Weil sie dafür Tastendrücke simuliert, verlangt macOS die Freigabe unter Bedienungshilfen.")
                    Text("Gesendet wird nur, was Claude angeboten hat – je Vorschlag einmal, höchstens 10 Minuten alt und nur, wenn das Fenster der Session vorne ist und ein Eingabefeld den Fokus hat. Sonst bleibt es bei der Zwischenablage.")
                }
            }

            Section {
                if model.server?.lastFocus == .denied {
                    LabeledContent {
                        Button("Automation erlauben …") { NSWorkspace.shared.open(WindowFocus.automationSettings) }
                    } label: {
                        StatusLabel(text: "Automation verweigert – nur die App wird aktiviert", symbol: "exclamationmark.triangle.fill", tint: .yellow)
                    }
                } else {
                    StatusLabel(text: model.server?.lastFocus == nil ? "Noch nicht genutzt" : "Zuletzt erfolgreich nach vorn geholt", symbol: "macwindow.on.rectangle", tint: .secondary)
                }
            } header: {
                Text("Session-Fenster")
            } footer: {
                Text("Tippst du am iPhone auf eine Session, kommt ihr Fenster nach vorn. Für Terminal und iTerm fragt macOS einmal nach der Automation-Erlaubnis.")
            }

            Section("Zuletzt direkt gesendet") {
                let sent = model.server?.replyLog ?? []
                if sent.isEmpty {
                    Text("Noch nichts gesendet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(sent.reversed().enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Antworten")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isTrusted = MacReply.isTrusted
        }
    }

    private func explanation(_ title: String, symbol: String, text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
        }
    }
}
