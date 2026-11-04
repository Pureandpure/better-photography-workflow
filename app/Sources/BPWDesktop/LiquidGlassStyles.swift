import SwiftUI

extension View {
    @ViewBuilder
    func creatorGlass(cornerRadius: CGFloat = 14, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.42), lineWidth: 0.7)
                }
        }
    }
}

struct GlassActionButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isProminent ? Color.white : Color.accentColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background {
                if isProminent {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.accentColor.opacity(configuration.isPressed ? 0.74 : 0.92))
                }
            }
            .creatorGlass(cornerRadius: 13, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
