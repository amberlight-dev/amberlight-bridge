import SwiftUI

struct MascotView: View {
    let mascot: Mascot
    let mood: MascotMood
    let celebratedAt: Date?
    var dimmed = false

    private static let ember = Color(red: 0.85, green: 0.12, blue: 0.08)
    private static let celebration: TimeInterval = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                draw(in: &ctx, size: size, time: time)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var frameInterval: Double {
        mood == .sleeping && celebrationAge(at: Date.now.timeIntervalSinceReferenceDate) == nil ? 1.0 / 10 : 1.0 / 30
    }

    private var accessibilityText: String {
        switch mood {
        case .working: String(localized: "\(mascot.title) arbeitet")
        case .sleeping: String(localized: "\(mascot.title) schläft")
        case .asking: String(localized: "\(mascot.title) hat eine Frage")
        }
    }

    private func celebrationAge(at time: Double) -> Double? {
        guard let celebratedAt else { return nil }
        let age = time - celebratedAt.timeIntervalSinceReferenceDate
        return (0..<Self.celebration).contains(age) ? age : nil
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let sprite = mascot.sprite
        let celebrationAge = celebrationAge(at: time)
        let celebrating = celebrationAge != nil
        let walking = mood == .working && !celebrating
        let rows = sprite.rows(step: Int(time * 6), swaying: walking && Int(time * 2) % 2 == 1, moving: walking || celebrating)
        let pixel = size.height / 16
        let unit = pixel * 2
        let spriteWidth = Double(MascotSprite.columns) * pixel
        let patrol = max(size.width - spriteWidth, 0) / 2
        let walkPhase = time * 0.45
        let heading = walking ? (cos(walkPhase) >= 0 ? 1 : -1) : 0
        let origin = CGPoint(
            x: (patrol + (walking ? sin(walkPhase) * patrol : 0)).rounded(),
            y: (size.height - Double(rows.count) * pixel - lift(celebrating: celebrating, walking: walking, time: time, unit: unit)).rounded()
        )

        func cell(_ row: Int, _ col: Int) -> CGRect {
            CGRect(x: origin.x + Double(col) * pixel, y: origin.y + Double(row) * pixel, width: pixel, height: pixel)
        }

        var eyes: [(row: Int, col: Int)] = []
        var shapes: [Character: Path] = [:]
        for (row, line) in rows.enumerated() {
            for (col, symbol) in line.enumerated() where symbol != "." {
                if symbol == MascotSprite.eye { eyes.append((row, col)) }
                if symbol == MascotSprite.eye && dimmed { continue }
                shapes[symbol == MascotSprite.eye ? sprite.lid : symbol, default: Path()].addRect(cell(row, col))
            }
        }
        for (symbol, shape) in shapes {
            ctx.fill(shape, with: .color(color(sprite.palette[symbol])))
        }

        if !dimmed {
            let blinking = time.truncatingRemainder(dividingBy: 4) < 0.15
            let closed = mood == .sleeping || celebrating || blinking
            for eye in eyes {
                let isUpperHalf = eye.row + 1 < rows.count && Array(rows[eye.row + 1])[eye.col] == MascotSprite.eye
                if closed && isUpperHalf { continue }
                ctx.fill(Path(cell(eye.row, eye.col + heading)), with: .color(color(sprite.palette[MascotSprite.eye])))
            }
        }

        if let celebrationAge {
            drawPetals(in: &ctx, size: size, around: origin.x, width: spriteWidth, pixel: pixel, age: celebrationAge, tint: sprite.petal)
        }

        let mark = CGPoint(x: origin.x + spriteWidth / 2, y: origin.y - unit * 1.2)
        if mood == .asking && !celebrating {
            drawGlyph("?", in: &ctx, at: mark, size: unit * 1.8, opacity: 0.9)
        } else if mood == .sleeping && !celebrating {
            let drift = time.truncatingRemainder(dividingBy: 3) / 3
            let anchor = CGPoint(x: origin.x + spriteWidth + unit * drift, y: origin.y - unit * drift * 1.5)
            drawGlyph("z", in: &ctx, at: anchor, size: unit * 1.4, opacity: 0.7 * (1 - drift))
        }
    }

    private func lift(celebrating: Bool, walking: Bool, time: Double, unit: Double) -> Double {
        if celebrating { return abs(sin(time * 7)) * unit * 1.4 }
        if walking { return abs(sin(time * 9)) * unit * 0.25 }
        if mood == .asking { return abs(sin(time * 2.5)) * unit * 0.2 }
        return 0
    }

    private func drawPetals(in ctx: inout GraphicsContext, size: CGSize, around x: Double, width: Double, pixel: Double, age: Double, tint: UInt32) {
        let fade = min(1, Self.celebration - age)
        for index in 0..<9 {
            let seed = Double(index)
            let spread = (seed * 0.618).truncatingRemainder(dividingBy: 1)
            let speed = size.height * (0.25 + 0.15 * (seed * 0.37).truncatingRemainder(dividingBy: 1))
            let start = size.height * (seed * 0.29).truncatingRemainder(dividingBy: 1)
            let y = (start + age * speed).truncatingRemainder(dividingBy: size.height)
            let petalX = x - pixel * 2 + (width + pixel * 4) * spread + sin(age * 3 + seed) * pixel
            let petal = CGRect(x: petalX, y: y, width: pixel * 0.8, height: pixel * 0.8)
            ctx.fill(Path(petal), with: .color(color(tint).opacity(fade)))
        }
    }

    private func color(_ rgb: UInt32?) -> Color {
        let rgb = rgb ?? 0xFFFFFF
        let red = Double(rgb >> 16 & 0xFF) / 255
        let green = Double(rgb >> 8 & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255
        guard dimmed else { return Color(red: red, green: green, blue: blue) }
        let glow = 0.25 + 0.45 * (0.3 * red + 0.59 * green + 0.11 * blue)
        return Color(red: 0.85 * glow, green: 0.12 * glow, blue: 0.08 * glow)
    }

    private func drawGlyph(_ glyph: String, in ctx: inout GraphicsContext, at point: CGPoint, size: Double, opacity: Double) {
        let ink: Color = dimmed ? Self.ember.opacity(0.5) : .white.opacity(opacity)
        let text = Text(glyph)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
        ctx.draw(text, at: point)
    }
}
