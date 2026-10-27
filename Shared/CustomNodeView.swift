import Charts
import SwiftUI

extension CustomWidgetDisplay.Tone {
    func color(dimmed: Bool) -> Color {
        let color: Color = switch self {
        case .green: WidgetInk.calm
        case .yellow: WidgetInk.busy
        case .red: WidgetInk.alarm
        case .blue: Color(red: 0.48, green: 0.72, blue: 1)
        case .gray: .white.opacity(0.55)
        }
        return WidgetInk.accent(color, dimmed: dimmed)
    }
}

struct CustomNodeEditing {
    var selected: String?
    var select: (String) -> Void
    var drop: (String, String?) -> Bool
}

extension EnvironmentValues {
    @Entry var customNodeEditing: CustomNodeEditing?
}

struct CustomNodeView: View {
    let node: CustomNode
    let display: CustomWidgetDisplay
    let span: GridSpan
    let dimmed: Bool
    let scale: CGFloat

    @Environment(\.standTypeface) private var typeface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.standAccent) private var standAccent
    @Environment(\.customNodeEditing) private var editing
    @State private var targeted = false

    var body: some View {
        if span.w >= node.minW ?? 1, span.h >= node.minH ?? 1, span.w <= node.maxW ?? .max, span.h <= node.maxH ?? .max {
            if let editing, let ref = node.ref {
                content
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(editing.selected == ref ? Color.accentColor : targeted ? Color.accentColor.opacity(0.6) : .clear,
                                          style: StrokeStyle(lineWidth: 1.5, dash: targeted && editing.selected != ref ? [4, 3] : []))
                            .padding(-3)
                    }
                    .contentShape(.rect)
                    .onTapGesture { editing.select(ref) }
                    .dropDestination(for: String.self) { items, _ in
                        items.first.map { editing.drop($0, ref) } ?? false
                    } isTargeted: { targeted = $0 }
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch node.type {
        case .vstack:
            VStack(alignment: horizontalAlignment, spacing: spacing) { children }
                .frame(maxWidth: .infinity, maxHeight: hasSpacer ? .infinity : nil, alignment: Alignment(horizontal: horizontalAlignment, vertical: .top))
        case .hstack:
            HStack(alignment: .center, spacing: spacing) { children }
        case .zstack:
            ZStack { children }
        case .spacer:
            Spacer(minLength: 0)
        case .text:
            label
        case .symbol:
            symbol
        case .dot:
            dot
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.timer(since: node.start ?? context.date, at: context.date))
            }
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color(opacity: 0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)
        case .ring:
            ring
                .frame(minWidth: 40 * scale, minHeight: 40 * scale)
        case .bar:
            bar
        case .line:
            if display.history.count > 1 { CustomLineChart(history: display.history, dimmed: dimmed) }
        case .bars:
            CustomBarChart(points: display.points, dimmed: dimmed)
        case .list:
            CustomPointList(points: display.points, dimmed: dimmed)
        case .pill:
            pill
        case .divider:
            Divider().overlay(WidgetInk.text(0.25, dimmed: dimmed))
        }
    }

    private static func timer(since start: Date, at date: Date) -> String {
        let elapsed = Duration.seconds(abs(date.timeIntervalSince(start)).rounded(.down))
        return elapsed >= .seconds(3600) ? elapsed.formatted(.time(pattern: .hourMinuteSecond)) : elapsed.formatted(.time(pattern: .minuteSecond))
    }

    private var children: some View {
        ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
            CustomNodeView(node: child, display: display, span: span, dimmed: dimmed, scale: scale)
        }
    }

    private var hasSpacer: Bool {
        node.children?.contains { $0.type == .spacer } == true
    }

    private var spacing: CGFloat { (node.spacing ?? 4) * scale }

    private var horizontalAlignment: HorizontalAlignment {
        switch node.align ?? .leading {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var points: CGFloat {
        let base: CGFloat = switch node.size ?? .m {
        case .xs: 11
        case .s: 15
        case .m: 20
        case .l: 32
        case .xl: 52
        }
        return max(11, base * scale)
    }

    private var font: Font {
        let weight: Font.Weight = node.bold == true ? .bold : .regular
        switch node.size ?? .m {
        case .xs: return .system(size: points, weight: node.bold == true ? .bold : .semibold)
        case .s, .m, .l, .xl: return typeface.font(size: points, weight: weight)
        }
    }

    private var customColor: Color? {
        switch node.color {
        case nil: nil
        case "accent": WidgetInk.accent(standAccent ?? StandAccent.amber, dimmed: dimmed)
        case let hex?: StandAccent.color(hex: hex).map { WidgetInk.accent($0, dimmed: dimmed) }
        }
    }

    private var toneColor: Color {
        customColor ?? (node.tone ?? .gray).color(dimmed: dimmed)
    }

    private func color(opacity: Double) -> Color {
        customColor ?? node.tone?.color(dimmed: dimmed) ?? WidgetInk.text(opacity, dimmed: dimmed)
    }

    private var pill: some View {
        HStack(spacing: 6 * scale) {
            Circle().fill(toneColor).frame(width: 7 * scale, height: 7 * scale)
            Text(node.text ?? "")
                .font(font)
                .foregroundStyle(toneColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 4 * scale)
        .background(toneColor.opacity(0.16), in: Capsule())
    }

    private var label: some View {
        Text(node.text ?? "")
            .font(font)
            .fontWidth(node.size == .xs ? .expanded : nil)
            .textCase(node.size == .xs ? .uppercase : nil)
            .tracking(node.size == .xs ? 1.2 : 0)
            .foregroundStyle(color(opacity: node.size == .xs || node.size == .s ? 0.7 : 0.95))
            .lineLimit(node.lines ?? 1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .smooth, value: node.text)
    }

    private var symbol: some View {
        Image(systemName: node.text ?? "circle")
            .font(.system(size: points, weight: .semibold))
            .foregroundStyle(color(opacity: 0.9))
            .symbolEffect(.pulse, options: .repeating, isActive: node.pulse == true && !reduceMotion)
    }

    private var dot: some View {
        let diameter = (node.width ?? 10) * scale
        let tone = toneColor
        return Circle()
            .fill(tone)
            .frame(width: diameter, height: diameter)
            .overlay {
                if node.pulse == true, !reduceMotion, !dimmed {
                    Circle()
                        .stroke(tone, lineWidth: 1.5)
                        .phaseAnimator([0.0, 1.0]) { ring, phase in
                            ring.scaleEffect(1 + phase * 1.6).opacity(0.7 * (1 - phase))
                        } animation: { phase in
                            phase == 0 ? .linear(duration: 0.01) : .easeOut(duration: 1.7)
                        }
                }
            }
            .padding(diameter * 0.3)
            .accessibilityHidden(true)
    }

    private var ring: some View {
        CustomRing(progress: node.progress ?? 0, tone: toneColor, lineWidth: node.width, animated: !reduceMotion) {
            children
        }
    }

    private var bar: some View {
        CustomBar(progress: node.progress ?? 0, tone: toneColor, height: max(4, (node.width ?? 6) * scale), animated: !reduceMotion)
    }
}

private struct CustomRing<Content: View>: View {
    let progress: Double
    let tone: Color
    let lineWidth: Double?
    let animated: Bool
    @ViewBuilder let content: Content

    @State private var drawn = false

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let stroke = lineWidth ?? max(4, diameter * 0.11)
            let shown = drawn || !animated ? progress : 0
            ZStack {
                Circle().stroke(tone.opacity(0.18), lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(
                        AngularGradient(colors: [tone.opacity(0.5), tone], center: .center, startAngle: .degrees(0), endAngle: .degrees(max(360 * progress, 1))),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(animated ? .smooth(duration: 1.1) : nil, value: shown)
                content
                    .padding(stroke * 1.2)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { drawn = true }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

private struct CustomBar: View {
    let progress: Double
    let tone: Color
    let height: CGFloat
    let animated: Bool

    @State private var drawn = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tone.opacity(0.18))
                Capsule()
                    .fill(tone)
                    .frame(width: proxy.size.width * (drawn || !animated ? progress : 0))
                    .animation(animated ? .smooth(duration: 0.9) : nil, value: progress)
            }
        }
        .frame(height: height)
        .onAppear { drawn = true }
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

struct CustomLineChart: View {
    let history: [CustomWidgetDisplay.Sample]
    let dimmed: Bool

    var body: some View {
        if history.count > 1 {
            Chart(Array(history.enumerated()), id: \.offset) { _, sample in
                LineMark(x: .value("Zeit", sample.at), y: .value("Wert", sample.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(ink(0.9))
                if varies {
                    AreaMark(x: .value("Zeit", sample.at), y: .value("Wert", sample.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [ink(0.25), .clear], startPoint: .top, endPoint: .bottom))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in AxisValueLabel().foregroundStyle(ink(0.5)) } }
        } else {
            Text("Der Verlauf füllt sich mit jedem Abruf.")
                .font(.caption)
                .foregroundStyle(ink(0.5))
        }
    }

    private var varies: Bool {
        Set(history.map(\.value)).count > 1
    }

    private func ink(_ opacity: Double) -> Color { WidgetInk.text(opacity, dimmed: dimmed) }
}

struct CustomBarChart: View {
    let points: [CustomWidgetDisplay.Point]
    let dimmed: Bool

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            BarMark(x: .value("Label", point.label), y: .value("Wert", point.value ?? 0))
                .foregroundStyle(ink(0.85))
                .cornerRadius(4)
        }
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(ink(0.6)) } }
    }

    private func ink(_ opacity: Double) -> Color { WidgetInk.text(opacity, dimmed: dimmed) }
}

struct CustomPointList: View {
    let points: [CustomWidgetDisplay.Point]
    let dimmed: Bool

    @Environment(\.standTypeface) private var typeface

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline) {
                        Text(point.label)
                            .foregroundStyle(ink(0.9))
                        Spacer(minLength: 8)
                        Text(point.text ?? "–")
                            .monospacedDigit()
                            .foregroundStyle(ink(0.6))
                            .layoutPriority(1)
                    }
                    .font(typeface.font(size: 15, weight: .regular))
                    .lineLimit(1)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func ink(_ opacity: Double) -> Color { WidgetInk.text(opacity, dimmed: dimmed) }
}
