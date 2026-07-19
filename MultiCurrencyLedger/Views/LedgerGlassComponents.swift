import SwiftUI

enum LedgerMotion {
    static let responsive = Animation.spring(response: 0.34, dampingFraction: 1)
    static let physical = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let reduced = Animation.easeOut(duration: 0.16)
    static let pressDown = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
    static let pressUp = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.10)

    static func press(isPressed: Bool) -> Animation {
        isPressed ? pressDown : pressUp
    }
}

struct LedgerGlassPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                LedgerMotion.press(isPressed: configuration.isPressed),
                value: configuration.isPressed
            )
    }
}

private struct LedgerContentSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(
                    reduceTransparency
                        ? Color(uiColor: .secondarySystemBackground)
                        : Color(uiColor: .secondarySystemGroupedBackground)
                )
            }
            .overlay {
                shape.stroke(Color(uiColor: .separator).opacity(reduceTransparency ? 0.5 : 0.22), lineWidth: 0.75)
            }
            .shadow(color: tint.opacity(0.035), radius: 8, y: 3)
    }
}

extension View {
    func ledgerContentSurface(cornerRadius: CGFloat = 26, tint: Color = HomePalette.accent) -> some View {
        modifier(LedgerContentSurfaceModifier(cornerRadius: cornerRadius, tint: tint))
    }

    // Compatibility bridge while feature screens move from decorative glass cards
    // to semantic content surfaces. New interactive chrome should use glassEffect.
    func ledgerGlassCard(cornerRadius: CGFloat = 26, tint: Color = HomePalette.accent) -> some View {
        ledgerContentSurface(cornerRadius: cornerRadius, tint: tint)
    }
}

extension Color {
    static func ledgerHex(_ value: String, fallback: Color = HomePalette.accent) -> Color {
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 || cleaned.count == 8,
              let number = UInt64(cleaned, radix: 16) else { return fallback }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        if cleaned.count == 8 {
            red = Double((number >> 24) & 0xFF) / 255
            green = Double((number >> 16) & 0xFF) / 255
            blue = Double((number >> 8) & 0xFF) / 255
            alpha = Double(number & 0xFF) / 255
        } else {
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
            alpha = 1
        }
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
