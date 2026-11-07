import Foundation
import UserNotifications

nonisolated enum CustomApprovalNotice {
    static let scheme = "amberlight-bridge"
    static let widgetIDKey = "widget"

    static func link(for id: UUID) -> String {
        "\(scheme)://widget/\(id.uuidString)"
    }

    static func widgetID(in url: URL) -> UUID? {
        guard url.scheme == scheme, url.host() == "widget" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    static func unapprovedOrigins(of definition: CustomWidgetDefinition) -> [String] {
        definition.isScripted
            ? definition.unconfirmedHosts.map { $0.origin ?? $0.url }
            : (definition.isConfirmed ? [] : [definition.origin ?? definition.baseURL])
    }

    @MainActor
    static func update(_ definition: CustomWidgetDefinition, store: CustomWidgetStore) {
        guard !BridgeModel.isTestHost else { return }
        let identifier = "approval-\(definition.id.uuidString)"
        let center = UNUserNotificationCenter.current()
        let hosts = unapprovedOrigins(of: definition)
        let missingSecrets = !store.missingSecrets(definition).isEmpty
        guard !hosts.isEmpty || missingSecrets else {
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "„\(definition.name)“ wartet auf dich")
        content.body = summary(hosts: hosts, missingSecrets: missingSecrets)
        content.userInfo = [widgetIDKey: definition.id.uuidString]
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }

    private static func summary(hosts: [String], missingSecrets: Bool) -> String {
        switch (hosts.isEmpty, missingSecrets) {
        case (false, true): return String(localized: "\(hosts.joined(separator: ", ")) freigeben und Zugangsdaten eintragen")
        case (false, false): return String(localized: "\(hosts.joined(separator: ", ")) freigeben")
        default: return String(localized: "Zugangsdaten eintragen")
        }
    }
}
