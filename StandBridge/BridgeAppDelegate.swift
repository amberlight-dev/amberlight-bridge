import AppKit
import Sparkle
import SwiftUI

@MainActor
final class BridgeAppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static var quitRequested = false
    private static weak var shared: BridgeAppDelegate?

    let model = BridgeModel()
    private(set) lazy var updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    private var statusItem: BridgeStatusItem?
    private var launchedAsLoginItem = false

    static func closeMenu() {
        shared?.statusItem?.close()
    }

    static func applyStatusItemVisibility() {
        shared?.statusItem?.applyVisibility()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        launchedAsLoginItem = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleQuit(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication)
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Self.quitRequested = true }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !BridgeModel.isTestHost else { return }
        statusItem = BridgeStatusItem(model: model, updater: updaterController.updater)
        if !BridgeStatusItem.isVisibleSetting && !launchedAsLoginItem { showMainWindow() }
    }

    @objc private func handleQuit(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        Self.quitRequested = true
        NSApplication.shared.terminate(nil)
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        Self.quitRequested = true
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus || !BridgeStatusItem.isVisibleSetting
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        showUpdateReminder("\(update.displayVersionString) (\(update.versionString))")
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        showUpdateReminder(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        showUpdateReminder(nil)
    }

    private func showUpdateReminder(_ version: String?) {
        model.availableUpdate = version
        statusItem?.showsUpdate = version != nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.quitRequested ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    private func showMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(BridgeWindow.id) == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            EnvironmentValues().openWindow(id: BridgeWindow.id)
        }
    }
}
