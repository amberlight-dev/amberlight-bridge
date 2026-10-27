import AppKit
import SwiftUI

struct DevicesView: View {
    let model: BridgeModel

    var body: some View {
        Form {
            Section("iPhone") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ConnectionLabel(contact: model.server?.lastClient, now: context.date)
                }
                if let contact = model.server?.lastClient {
                    LabeledContent("Adresse", value: contact.host)
                }
                LabeledContent("Anordnung", value: model.layout.revision == 0 ? "noch nicht übernommen" : "Revision \(model.layout.revision)")
            }

            if let server = model.server, let link = model.pairingLink {
                Section {
                    HStack(alignment: .top, spacing: 20) {
                        QRCodeImage(text: link)
                            .frame(width: 168, height: 168)
                            .padding(10)
                            .background(.white, in: .rect(cornerRadius: 12))
                            .accessibilityLabel("QR-Code zum Koppeln")
                        VStack(alignment: .leading, spacing: 10) {
                            if model.tokenRenewed {
                                StatusLabel(text: "Neuer, längerer Kopplungscode – iPhone bitte neu koppeln", symbol: "exclamationmark.triangle.fill", tint: .yellow)
                            }
                            Text("Gekoppelt wird nur über diesen QR-Code: In der Amberlight-App beim Einrichten oder unter Einstellungen „Neu koppeln“ wählen und scannen.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Koppeln")
                }

                Section("Netzwerk") {
                    LabeledContent("Adresse", value: server.baseURL)
                    LabeledContent("Port", value: "\(server.port)")
                    LabeledContent("Bonjour", value: BridgeServer.serviceType)
                    LabeledContent("Server") { ServerStatusLabel(status: server.status) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Geräte")
    }
}

struct ConnectionLabel: View {
    let contact: ClientContact?
    let now: Date

    var body: some View {
        if let contact, contact.isOnline(now: now) {
            StatusLabel(text: "iPhone verbunden", symbol: "circle.fill", tint: .green)
        } else if let contact {
            StatusLabel(text: "Zuletzt \(contact.at.formatted(.relative(presentation: .named)))", symbol: "circle", tint: .secondary)
        } else {
            StatusLabel(text: "Noch kein iPhone seit dem Start", symbol: "circle.dashed", tint: .secondary)
        }
    }
}

struct ServerStatusLabel: View {
    let status: BridgeServer.Status

    var body: some View {
        switch status {
        case .running: StatusLabel(text: "Läuft", symbol: "checkmark.circle.fill", tint: .green)
        case .starting: StatusLabel(text: "Startet …", symbol: "hourglass", tint: .secondary)
        case .failed(let reason): StatusLabel(text: reason, symbol: "exclamationmark.triangle.fill", tint: .yellow)
        }
    }
}

struct StatusLabel: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }
}
