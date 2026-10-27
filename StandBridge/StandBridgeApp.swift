import SwiftUI

@main
struct StandBridgeApp: App {
    @NSApplicationDelegateAdaptor(BridgeAppDelegate.self) private var delegate

    var body: some Scene {
        Window("Amberlight Bridge", id: BridgeWindow.id) {
            BridgeWindow(model: delegate.model, updater: delegate.updaterController.updater)
        }
        .defaultSize(width: 1240, height: 760)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: "openLayout") ? .presented : .suppressed)
        .restorationBehavior(.disabled)
    }
}
