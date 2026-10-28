import Foundation

nonisolated enum CustomWidgetShare {
    enum ImportError: Error, Equatable {
        case notAWidget, tooLong, unreadable, unsupportedVersion, invalid(CustomRequestError)

        var message: String {
            switch self {
            case .notAWidget: String(localized: "Kein Amberlight-Widget – der Text beginnt nicht mit „\(CustomWidgetShare.prefix)“")
            case .tooLong: String(localized: "Text ist zu lang für eine Widget-Konfiguration")
            case .unreadable: String(localized: "Konfiguration ist beschädigt")
            case .unsupportedVersion: String(localized: "Konfiguration stammt aus einer neueren Amberlight-Version")
            case .invalid(let error): error.message
            }
        }
    }

    static let prefix = "stand-widget:"
    static let version = 1
    static let maxLength = 64 << 10

    private struct Payload: Codable {
        var v: Int
        var widget: CustomWidgetDefinition
    }

    static func export(_ definition: CustomWidgetDefinition) -> String {
        var shared = definition
        shared.confirmedOrigin = nil
        shared.endpoint.headers.removeAll { CustomRequest.isSensitive($0.name) }
        shared.endpoint.query.removeAll { CustomRequest.isSensitive($0.name) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(Payload(v: version, widget: shared))) ?? Data()
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) throws(ImportError) -> CustomWidgetDefinition {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxLength else { throw .tooLong }
        guard trimmed.hasPrefix(prefix) else { throw .notAWidget }
        var base64 = String(trimmed.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw .unreadable }
        guard payload.v <= version else { throw .unsupportedVersion }
        var definition = payload.widget
        definition.id = UUID()
        definition.confirmedOrigin = nil
        definition.interval = definition.clampedInterval
        do {
            try CustomRequest.validate(definition)
        } catch {
            throw .invalid(error)
        }
        return definition
    }
}
