import AppKit

enum WindowSnapshot {
    static func writeIfRequested() {
        guard let prefix = UserDefaults.standard.string(forKey: "snapshot") else { return }
        Task {
            try? await Task.sleep(for: .seconds(UserDefaults.standard.double(forKey: "snapshotDelay").nonZero ?? 5))
            for (index, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.width > 200 {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath: "\(prefix)-\(index).png"))
            }
        }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
