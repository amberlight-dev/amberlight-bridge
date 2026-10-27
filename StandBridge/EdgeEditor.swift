import SwiftUI

struct EdgeEditor: View {
    let page: StandPage
    let edges: EdgeConfig
    let onChange: (EdgeConfig) -> Void

    private static let rail: CGFloat = 84
    private static let band: CGFloat = 58
    private static let spacing: CGFloat = 8
    private static let inset: CGFloat = 12

    @State private var width: CGFloat = 900

    private var canvasHeight: CGFloat {
        let canvasWidth = width - 2 * Self.inset - 3 * Self.rail - 3 * Self.spacing
        return max(canvasWidth, 120) * PageCanvas.screen.height / PageCanvas.screen.width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            frame
            HStack(spacing: 24) {
                Toggle(isOn: Binding(
                    get: { edges.slots[.perimeter] == .secondsOrbit },
                    set: { on in change { $0.slots[.perimeter] = on ? .secondsOrbit : nil } }
                )) {
                    Label(MicroWidget.secondsOrbit.title, systemImage: MicroWidget.secondsOrbit.symbol)
                }
                Toggle(isOn: Binding(
                    get: { edges.hiddenPages.contains(page.id) },
                    set: { hidden in change { if hidden { $0.hiddenPages.insert(page.id) } else { $0.hiddenPages.remove(page.id) } } }
                )) {
                    Label("Auf „\(page.name)“ ausblenden", systemImage: "eye.slash")
                }
            }
            .toggleStyle(.switch)
            Text("Platz anklicken und ein Micro-Widget wählen. Die Plätze gelten für alle Seiten, die Kamera sitzt hier links.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var frame: some View {
        VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                target(.topLeading).frame(width: Self.rail * 2 + Self.spacing)
                target(.top)
                target(.topTrailing).frame(width: Self.rail)
            }
            .frame(height: Self.band)
            HStack(spacing: Self.spacing) {
                VStack(spacing: Self.spacing) {
                    target(.earBefore)
                    Capsule()
                        .fill(.primary.opacity(0.35))
                        .frame(width: 14, height: 46)
                        .accessibilityLabel("Kamera")
                    target(.earAfter)
                }
                .frame(width: Self.rail)
                target(.leading).frame(width: Self.rail)
                PageCanvas(page: page, selectedItem: nil, onSelect: { _ in }, onMove: { _, _ in }, onResize: { _, _ in }, onRemove: { _ in })
                    .allowsHitTesting(false)
                    .opacity(edges.hiddenPages.contains(page.id) ? 0.35 : 0.75)
                target(.trailing).frame(width: Self.rail)
            }
            .frame(height: canvasHeight)
            HStack(spacing: Self.spacing) {
                target(.bottomLeading).frame(width: Self.rail * 2 + Self.spacing)
                target(.bottom)
                target(.bottomTrailing).frame(width: Self.rail)
            }
            .frame(height: Self.band)
        }
        .padding(Self.inset)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(.black.opacity(0.88), in: .rect(cornerRadius: 40, style: .continuous))
        .overlay {
            if edges.slots[.perimeter] == .secondsOrbit {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [2, 6]))
                    .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func target(_ slot: MicroSlot) -> some View {
        EdgeSlotTarget(slot: slot, title: title(of: slot), current: edges.slots[slot]) { widget in
            change { $0.slots[slot] = widget }
        }
    }

    private func title(of slot: MicroSlot) -> String {
        switch slot {
        case .earBefore: "Ohr oben"
        case .earAfter: "Ohr unten"
        default: slot.title
        }
    }

    private func change(_ transform: (inout EdgeConfig) -> Void) {
        var next = edges
        transform(&next)
        guard next != edges else { return }
        onChange(next)
    }
}

private struct EdgeSlotTarget: View {
    let slot: MicroSlot
    let title: String
    let current: MicroWidget?
    let onPick: (MicroWidget?) -> Void

    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Menu {
            Picker(title, selection: Binding(get: { current }, set: { onPick($0) })) {
                Text("Leer").tag(MicroWidget?.none)
                ForEach(MicroWidget.allCases.filter { $0.fits(slot) }) { widget in
                    Label(widget.title, systemImage: widget.symbol).tag(MicroWidget?.some(widget))
                }
            }
            .pickerStyle(.inline)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: current?.symbol ?? "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text(current?.title ?? title)
                    .font(.caption2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white.opacity(current == nil ? 0.55 : 0.95))
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.shape.fill(.white.opacity(current == nil ? 0.05 : 0.16)))
            .overlay {
                Self.shape.strokeBorder(.white.opacity(current == nil ? 0.3 : 0.5), style: StrokeStyle(lineWidth: 1, dash: current == nil ? [4, 3] : []))
            }
            .contentShape(Self.shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(current.map { "\(title): \($0.title)" } ?? "\(title): leer")
        .accessibilityLabel("\(title): \(current?.title ?? "leer")")
    }
}
