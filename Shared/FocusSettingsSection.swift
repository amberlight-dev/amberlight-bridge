import SwiftUI

struct FocusSettingsSection: View {
    @Binding var focus: Int
    @Binding var rest: Int

    private static let presets = [25, 50]

    var body: some View {
        Section("Fokus-Timer") {
            Picker("Fokus", selection: Binding(
                get: { Self.presets.contains(focus) ? focus : 0 },
                set: { focus = $0 == 0 ? 30 : $0 }
            )) {
                ForEach(Self.presets, id: \.self) { Text("\($0) Min").tag($0) }
                Text("Eigene").tag(0)
            }
            if !Self.presets.contains(focus) {
                Stepper("Eigene Dauer: \(focus) Min", value: $focus, in: 5...180, step: 5)
            }
            Picker("Pause", selection: $rest) {
                ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) Min").tag($0) }
            }
        }
    }
}
