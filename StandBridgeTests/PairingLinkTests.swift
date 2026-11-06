import Foundation
import Testing
@testable import StandBridge

@MainActor
struct PairingLinkTests {
    @Test func carriesFallbackOnlyWhenKnown() {
        let withFallback = URLComponents(string: BridgeIdentity.pairingLink(baseURL: "http://mac.local:7420", fallbackURL: "http://192.168.1.20:7420", token: "abcd"))
        let without = URLComponents(string: BridgeIdentity.pairingLink(baseURL: "http://mac.local:7420", fallbackURL: nil, token: "abcd"))
        #expect(withFallback?.queryItems?.first { $0.name == "fallback" }?.value == "http://192.168.1.20:7420")
        #expect(without?.queryItems?.contains { $0.name == "fallback" } == false)
    }

    @Test func lanAddressIsUsableIPv4() {
        guard let ip = BridgeIdentity.lanIPv4 else { return }
        let octets = ip.split(separator: ".").compactMap { UInt8($0) }
        #expect(octets.count == 4)
        #expect(!ip.hasPrefix("169.254.") && !ip.hasPrefix("127."))
    }
}
