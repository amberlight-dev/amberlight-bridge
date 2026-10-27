import AppKit
import Sparkle
import SwiftUI

@MainActor
final class BridgeStatusItem: NSObject {
    private static let autosaveName = "StandBridgeStatus"
    static let visibleKey = "showsMenuBarIcon"
    static var isVisibleSetting: Bool { UserDefaults.standard.object(forKey: visibleKey) == nil || UserDefaults.standard.bool(forKey: visibleKey) }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    var showsUpdate = false {
        didSet {
            item.button?.image = BridgeGlyph.image(size: 18, template: true, badge: showsUpdate)
            item.button?.setAccessibilityLabel(showsUpdate ? String(localized: "Amberlight Bridge, Update verfügbar") : "Amberlight Bridge")
        }
    }

    init(model: BridgeModel, updater: SPUUpdater) {
        super.init()
        item.autosaveName = Self.autosaveName
        item.behavior = []
        item.isVisible = Self.isVisibleSetting
        if let button = item.button {
            button.image = BridgeGlyph.image(size: 18, template: true)
            button.setAccessibilityLabel("Amberlight Bridge")
            button.target = self
            button.action = #selector(toggle(_:))
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: BridgeMenu(model: model, updater: updater))
    }

    func close() {
        popover.performClose(nil)
    }

    func applyVisibility() {
        close()
        item.isVisible = Self.isVisibleSetting
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
