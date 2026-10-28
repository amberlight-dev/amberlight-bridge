import Sparkle
import SwiftUI

struct BridgeMenu: View {
    let model: BridgeModel
    let updater: SPUUpdater
    @AppStorage(MacReply.directReplyKey) private var directReply = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let isConnected = model.server?.lastClient?.isOnline(now: context.date) == true
            VStack(alignment: .leading, spacing: 8) {
                header(now: context.date)
                Divider()
                if !isConnected, let link = model.pairingLink {
                    pairing(link)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 2) {
                    action(String(localized: "Amberlight Bridge öffnen"), symbol: "macwindow", key: "o") { show(model.sidebar) }
                    action(String(localized: "Anordnung bearbeiten …"), symbol: "rectangle.3.group", key: "e") { show(model.layout.pages.first.map { .page($0.id) }) }
                    if isConnected {
                        action(String(localized: "Weiteres iPhone koppeln …"), symbol: "qrcode", key: "k") { show(.devices) }
                    }
                    if directReply && !MacReply.isTrusted {
                        action(String(localized: "Bedienungshilfen freigeben …"), symbol: "exclamationmark.triangle.fill", tint: .yellow) {
                            NSWorkspace.shared.open(MacReply.accessibilitySettings)
                        }
                    }
                }
                if let message = model.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                }
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    action(String(localized: "Über Amberlight Bridge"), symbol: "info.circle", trailing: Bundle.main.versionLabel) {
                        NSApp.activate()
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                    if let version = model.availableUpdate {
                        action(String(localized: "Update auf \(version) installieren …"), symbol: "arrow.down.circle.fill", tint: StandAccent.bridgeTint, key: "u", perform: checkForUpdates)
                    } else {
                        action(String(localized: "Nach Updates suchen …"), symbol: "arrow.down.circle", key: "u", perform: checkForUpdates)
                    }
                    action(String(localized: "Amberlight Bridge beenden"), symbol: "power", key: "q") {
                        BridgeAppDelegate.quitRequested = true
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
        .frame(width: 300)
        .tint(StandAccent.bridgeTint)
        .onAppear { model.refresh() }
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: BridgeGlyph.image(size: 26, template: false))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Amberlight Bridge")
                    .font(.headline)
                HStack(spacing: 6) {
                    if let server = model.server {
                        ServerStatusLabel(status: server.status)
                            .labelStyle(.iconOnly)
                        Text("Port \(server.port)")
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                    }
                    ConnectionLabel(contact: model.server?.lastClient, now: now)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 8)
    }

    private func pairing(_ link: String) -> some View {
        VStack(spacing: 10) {
            QRCodeImage(text: link)
                .frame(width: 168, height: 168)
                .padding(10)
                .background(.white, in: .rect(cornerRadius: 12))
                .accessibilityLabel("QR-Code zum Koppeln")
            if model.tokenRenewed {
                StatusLabel(text: String(localized: "Neuer Kopplungscode – iPhone bitte neu koppeln"), symbol: "exclamationmark.triangle.fill", tint: .yellow)
                    .font(.caption)
            }
            Text("In der Amberlight-App beim Einrichten oder unter Einstellungen „Neu koppeln“ scannen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func action(_ title: String, symbol: String, tint: Color? = nil, trailing: String? = nil, key: KeyEquivalent? = nil, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                    .frame(width: 20)
                Text(title)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
        .keyboardShortcut(key.map { KeyboardShortcut($0) })
    }

    private func checkForUpdates() {
        NSApp.activate()
        updater.checkForUpdates()
    }

    private func show(_ item: BridgeSidebarItem?) {
        if let item { model.sidebar = item }
        openWindow(id: BridgeWindow.id)
        NSApp.activate()
        BridgeAppDelegate.closeMenu()
    }
}

extension Bundle {
    var versionLabel: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

private struct MenuRowStyle: ButtonStyle {
    @State private var hovers = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(hovers || configuration.isPressed ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
            .onHover { hovers = $0 }
    }
}
