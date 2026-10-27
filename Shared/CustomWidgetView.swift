import SwiftUI

struct CustomWidgetView: View {
    let display: CustomWidgetDisplay?
    let span: GridSpan
    let dimmed: Bool
    let notice: String

    @Environment(\.standTypeface) private var typeface

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let display, display.root != nil || display.text != nil || !display.points.isEmpty {
                    content(display, size: proxy.size)
                } else if span.w == 1 {
                    Image(systemName: display?.symbol ?? "square.stack.3d.up")
                        .font(.title2)
                        .foregroundStyle(ink(0.6))
                        .accessibilityLabel(display?.error ?? notice)
                } else {
                    Label(display?.error ?? notice, systemImage: display?.symbol ?? "square.stack.3d.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink(0.6))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func content(_ display: CustomWidgetDisplay, size: CGSize) -> some View {
        if let root = display.root {
            CustomNodeView(node: root, display: display, span: span, dimmed: dimmed, scale: min(max(min(size.height / 120, size.width / 150), 0.5), 1.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if span.w == 1 {
            core(display, size: min(size.height * 0.42, size.width / 2.6), showsCaption: span.h > 1)
        } else if span.h == 1 {
            core(display, size: min(size.height * 0.5, size.width / 4), showsCaption: display.lines?.isEmpty ?? true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                header(display)
                ForEach(Array((display.lines ?? []).enumerated()), id: \.offset) { _, line in lineText(line) }
                detail(display)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func core(_ display: CustomWidgetDisplay, size: CGFloat, showsCaption: Bool) -> some View {
        VStack(spacing: 4) {
            if display.style == .gauge, let progress = display.progress {
                Gauge(value: progress) { EmptyView() } currentValueLabel: { value(display, size: size * 0.42) }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(ink(0.9))
                    .scaleEffect(max(size / 34, 0.8))
                    .frame(height: size * 1.6)
            } else if display.style == .status, span.w == 1 {
                statusDot(display, size: size * 0.7)
                value(display, size: size * 0.32)
            } else {
                HStack(spacing: size * 0.18) {
                    if display.style == .status { statusDot(display, size: size * 0.32) }
                    value(display, size: size)
                }
            }
            if showsCaption { caption(display.caption) }
            else if span.w > 1, let line = display.lines?.first { lineText(line) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func header(_ display: CustomWidgetDisplay) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if display.style == .status { statusDot(display, size: 12) }
                value(display, size: 34).fixedSize()
                Spacer(minLength: 6)
                caption(display.caption).fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if display.style == .status { statusDot(display, size: 10) }
                    value(display, size: 28)
                }
                caption(display.caption)
            }
        }
    }

    @ViewBuilder
    private func detail(_ display: CustomWidgetDisplay) -> some View {
        switch display.style {
        case .line where display.history.count > 1:
            CustomLineChart(history: display.history, dimmed: dimmed)
        case .bar where !display.points.isEmpty:
            CustomBarChart(points: display.points, dimmed: dimmed)
        case .gauge:
            if let progress = display.progress {
                ProgressView(value: progress)
                    .tint(ink(0.9))
                    .padding(.top, 4)
            }
        case .line:
            Text("Der Verlauf füllt sich mit jedem Abruf.")
                .font(.caption)
                .foregroundStyle(ink(0.5))
        default:
            if !display.points.isEmpty { CustomPointList(points: display.points, dimmed: dimmed) }
        }
    }

    private func value(_ display: CustomWidgetDisplay, size: CGFloat) -> some View {
        Text(display.text ?? "–")
            .font(typeface.font(size: size))
            .foregroundStyle(display.style == .status ? tone(display.tone) : ink(0.95))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }

    private func lineText(_ text: String) -> some View {
        Text(text)
            .font(typeface.font(size: 15, weight: .regular))
            .foregroundStyle(ink(0.7))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .fontWidth(.expanded)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(ink(0.7))
            .lineLimit(1)
    }

    private func statusDot(_ display: CustomWidgetDisplay, size: CGFloat) -> some View {
        Circle()
            .fill(tone(display.tone))
            .frame(width: size, height: size)
            .shadow(color: dimmed ? .clear : tone(display.tone).opacity(0.6), radius: size * 0.4)
    }

    private func ink(_ opacity: Double) -> Color {
        WidgetInk.text(opacity, dimmed: dimmed)
    }

    private func tone(_ tone: CustomWidgetDisplay.Tone?) -> Color {
        (tone ?? .gray).color(dimmed: dimmed)
    }
}
