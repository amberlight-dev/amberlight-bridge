import SwiftUI

struct BackgroundTintSection: View {
    let style: BackgroundStyle
    @Binding var tint: BackgroundTint

    @Environment(\.self) private var environment

    var body: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(BackgroundTint.palette, id: \.self) { hex in
                    swatch(hex)
                }
                ColorPicker("Eigene Farbe", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
            }
            .padding(.vertical, 4)

            LabeledContent("Helligkeit") {
                Slider(value: brightness, in: BackgroundTint.brightnessRange)
                    .frame(maxWidth: 220)
            }
            Toggle("Dezenter Verlauf", isOn: gradient)

            if style == .pulse {
                Picker("Tempo", selection: tempo) {
                    ForEach(PulseTempo.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Reagiert auf Sessions", isOn: reactive)
            }
        } header: {
            Text(style == .pulse ? "Puls" : "Farbe")
        } footer: {
            Text(style == .pulse
                ? "Atmet langsam. Reagiert er auf Sessions, wird er schneller, solange gearbeitet wird, und leuchtet kurz auf, wenn etwas fertig ist."
                : "Sehr helle Farben werden gedämpft, damit Schrift lesbar bleibt.")
        }
    }

    private func swatch(_ hex: String) -> some View {
        let rgb = BackgroundTint.rgb(hex) ?? (0, 0, 0)
        let isSelected = tint.resolvedHex == hex
        return Button {
            tint.hex = hex
        } label: {
            Circle()
                .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.9 : 0.15), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hex)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customColor: Binding<Color> {
        Binding {
            let rgb = tint.rgb
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        } set: { color in
            let resolved = color.resolve(in: environment)
            tint.hex = BackgroundTint.hex(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
        }
    }

    private var brightness: Binding<Double> {
        Binding { tint.resolvedBrightness } set: { tint.brightness = $0 }
    }

    private var gradient: Binding<Bool> {
        Binding { tint.resolvedGradient } set: { tint.gradient = $0 }
    }

    private var tempo: Binding<PulseTempo> {
        Binding { tint.resolvedTempo } set: { tint.tempo = $0.rawValue }
    }

    private var reactive: Binding<Bool> {
        Binding { tint.resolvedReactive } set: { tint.reactive = $0 }
    }
}
