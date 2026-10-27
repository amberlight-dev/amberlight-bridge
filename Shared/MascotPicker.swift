import SwiftUI

struct MascotPicker: View {
    @Binding var selection: Mascot?
    var offersStandard = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if offersStandard {
                    option(nil, title: String(localized: "Standard")) {
                        Image(systemName: "circle.dashed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Mascot.allCases) { mascot in
                    option(mascot, title: mascot.title) {
                        MascotView(mascot: mascot, mood: .working, celebratedAt: nil)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func option(_ mascot: Mascot?, title: String, @ViewBuilder preview: () -> some View) -> some View {
        let selected = selection == mascot
        return Button {
            selection = mascot
        } label: {
            VStack(spacing: 6) {
                preview()
                    .frame(width: 72, height: 64)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
