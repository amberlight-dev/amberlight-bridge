import AppKit

enum BridgeGlyph {
    static let amber = NSColor(srgbRed: 1, green: 0xC5 / 255, blue: 0x66 / 255, alpha: 1)

    static func image(size: CGFloat, template: Bool, badge: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let line = rect.width * 0.11
            let arch = NSBezierPath()
            arch.lineWidth = line
            arch.lineCapStyle = .round
            let base = rect.minY + rect.height * 0.22
            arch.move(to: NSPoint(x: rect.minX + line, y: base))
            arch.curve(
                to: NSPoint(x: rect.maxX - line, y: base),
                controlPoint1: NSPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY * 0.95),
                controlPoint2: NSPoint(x: rect.maxX - rect.width * 0.2, y: rect.maxY * 0.95)
            )
            (template ? NSColor.black : NSColor.labelColor).setStroke()
            arch.stroke()
            let dot = rect.width * 0.24
            let circle = NSBezierPath(ovalIn: NSRect(x: rect.midX - dot / 2, y: base - dot * 0.15, width: dot, height: dot))
            (template ? NSColor.black : amber).setFill()
            circle.fill()
            if badge {
                let badgeRect = NSRect(x: rect.maxX - rect.width * 0.3, y: rect.maxY - rect.height * 0.3, width: rect.width * 0.3, height: rect.height * 0.3)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: badgeRect.insetBy(dx: -line * 0.8, dy: -line * 0.8)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: badgeRect).fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}
