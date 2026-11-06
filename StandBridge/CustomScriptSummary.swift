import SwiftUI

struct CustomScriptSummary: View {
    let definition: CustomWidgetDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Darf kontaktieren") {
                VStack(alignment: .leading, spacing: 6) {
                    if definition.scriptHosts.isEmpty {
                        Text("Keinen Host – das Skript rechnet nur lokal.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(definition.scriptHosts, id: \.self) { host in
                        CustomScriptHostLabel(host: host)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            GroupBox("Skript") {
                ScrollView {
                    Text(definition.script ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 180)
            }
            Text("Dieses Widget führt Code aus. Er läuft abgeschottet ohne Datei- und Netzzugriff und erreicht nur die Hosts oben, und das erst, wenn du sie freigibst. Zugangsdaten sieht das Skript nie.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CustomScriptHostLabel: View {
    let host: CustomWidgetDefinition.ScriptHost

    var body: some View {
        HStack(spacing: 8) {
            Text(host.origin ?? host.url)
                .font(.system(.body, design: .monospaced))
            if host.writes {
                Text("schreibt")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
            if host.needsSecret {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                    .help(host.auth.kind.title)
            }
            if CustomRequest.usesPlainHTTP(host.url) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Unverschlüsselt (http)")
            }
        }
    }
}

struct CustomScriptCard: View {
    @Binding var draft: CustomWidgetDefinition
    @Binding var secrets: [String: CustomSecret]
    let status: ConnectionStatus
    let onTest: () -> Void

    var body: some View {
        StudioCard(title: String(localized: "Skript"), subtitle: String(localized: "Läuft abgeschottet auf diesem Mac. Hosts gibst nur du hier frei, Zugangsdaten bleiben im Schlüsselbund.")) {
            ForEach(draft.scriptHosts, id: \.self) { host in
                hostRow(host)
                Divider()
            }
            ScrollView {
                Text(draft.script ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            HStack(spacing: 12) {
                Button(action: onTest) {
                    Label(status == .idle ? "Ausführen & testen" : "Erneut ausführen", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r")
                .disabled(!draft.isConfirmed || status == .testing)
                statusLabel
            }
        }
    }

    private func hostRow(_ host: CustomWidgetDefinition.ScriptHost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CustomScriptHostLabel(host: host)
                Spacer()
                if draft.unconfirmedHosts.contains(host) {
                    Button(host.writes ? "Lesen & Schreiben freigeben" : "Freigeben") { confirm(host) }
                } else {
                    Label("Freigegeben", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }
            if host.writes, draft.unconfirmedHosts.contains(host) {
                Label("Das Skript darf hier auch Daten ändern oder löschen (POST, PUT, PATCH, DELETE).", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if host.needsSecret, let origin = host.origin {
                secretFields(host.auth.kind, origin: origin)
            }
        }
    }

    @ViewBuilder
    private func secretFields(_ kind: CustomWidgetDefinition.AuthKind, origin: String) -> some View {
        let binding = Binding(get: { secrets[origin] ?? CustomSecret() }, set: { secrets[origin] = $0 })
        if kind == .basic {
            TextField("Benutzer", text: binding.username)
        }
        SecureField(kind.title, text: binding.value)
        if binding.wrappedValue.value.isEmpty {
            Label("Zugangsdaten fehlen", systemImage: "key.slash")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private func confirm(_ host: CustomWidgetDefinition.ScriptHost) {
        draft.confirmedHosts = (draft.confirmedHosts ?? []).filter { $0.origin != host.origin } + [host]
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .idle: EmptyView()
        case .testing: ProgressView().controlSize(.small)
        case .connected(let bytes):
            Label("Ergebnis · \(bytes.formatted(.byteCount(style: .file)))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
