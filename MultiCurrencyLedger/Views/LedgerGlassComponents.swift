import SwiftUI
import UIKit

enum LedgerLayout {
    static let pagePadding: CGFloat = 16
    static let compactSpacing: CGFloat = 8
    static let controlSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    static let cornerSmall: CGFloat = 12
    static let cornerMedium: CGFloat = 20
    static let cornerLarge: CGFloat = 28
    static let minimumHitSize: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 56
}

enum LedgerMotion {
    static let responsive = Animation.easeInOut(duration: 0.24)
    static let physical = Animation.spring(response: 0.28, dampingFraction: 0.84)
    static let reduced = Animation.easeOut(duration: 0.16)
    static let pressDown = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
    static let pressUp = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.10)

    static func press(isPressed: Bool) -> Animation {
        isPressed ? pressDown : pressUp
    }
}

enum LedgerTypography {
    static let amount = LedgerFont.semibold(size: 20, relativeTo: .title3)
    static let largeAmount = LedgerFont.semibold(size: 34, relativeTo: .title2)
    static let receiptDate = LedgerFont.regular(size: 30, relativeTo: .title2)
    static let receiptMeta = LedgerFont.regular(size: 12, relativeTo: .caption)
}

/// Ioskeley Mono is the ledger's preferred face. PingFang is intentionally
/// used as the CJK fallback so Chinese copy keeps the same calm, compact
/// rhythm when the custom face is unavailable.
enum LedgerFont {
    static func regular(size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        resolved("Ioskeley Mono", fallback: "PingFangSC-Regular", size: size, relativeTo: style)
    }

    static func semibold(size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        resolved("Ioskeley Mono Semibold", fallback: "PingFangSC-Semibold", size: size, relativeTo: style)
    }

    private static func resolved(
        _ preferred: String,
        fallback: String,
        size: CGFloat,
        relativeTo style: Font.TextStyle
    ) -> Font {
        guard UIFont(name: preferred, size: size) == nil else {
            return .custom(preferred, size: size, relativeTo: style)
        }
        return .custom(fallback, size: size, relativeTo: style)
    }
}

enum LedgerPalette {
    /// Structural color is deliberately monochrome. Financial meaning still
    /// comes from signs, labels, and semantic system roles rather than a brand
    /// hue competing with the ledger content.
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.96, alpha: 1)
            : UIColor(white: 0.055, alpha: 1)
    })
    static let invertedInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.055, alpha: 1)
            : UIColor(white: 0.98, alpha: 1)
    })
    static let mutedInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.72, alpha: 1)
            : UIColor(white: 0.38, alpha: 1)
    })
    static let accent = ink
    static let environment = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.045, alpha: 1)
            : UIColor(red: 236 / 255, green: 234 / 255, blue: 227 / 255, alpha: 1)
    })
    static let environmentLift = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.105, alpha: 1)
            : UIColor(red: 236 / 255, green: 234 / 255, blue: 227 / 255, alpha: 1)
    })
    static let background = environment
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.105, alpha: 0.96)
            : UIColor(red: 250 / 255, green: 250 / 255, blue: 248 / 255, alpha: 0.96)
    })
    static let raisedSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.14, alpha: 1)
            : UIColor(white: 1, alpha: 1)
    })
    static let selectionFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 1)
            : UIColor(red: 224 / 255, green: 224 / 255, blue: 220 / 255, alpha: 1)
    })
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.18)
            : UIColor(white: 0, alpha: 0.16)
    })
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let separator = hairline
}

enum EntryFloatingCardAppearance {
    static let backgroundOpacity = 0.95

    static func surface(for colorScheme: ColorScheme) -> Color {
        (colorScheme == .dark ? Color(white: 0.10) : .white)
            .opacity(backgroundOpacity)
    }
}

private struct LedgerForceSimplifiedGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var ledgerForceSimplifiedGlass: Bool {
        get { self[LedgerForceSimplifiedGlassKey.self] }
        set { self[LedgerForceSimplifiedGlassKey.self] = newValue }
    }
}

struct LedgerPageBackground: View {
    var body: some View {
        LinearGradient(
            colors: [LedgerPalette.environment, LedgerPalette.environmentLift],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
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

enum LedgerSurfaceRole {
    case functional
    case summary
    case canvas
    case floatingControl
    case centeredActionPanel
    case sheetChrome

    var defaultCornerRadius: CGFloat {
        switch self {
        case .functional: LedgerLayout.cornerMedium
        case .canvas: 40
        case .floatingControl: LedgerLayout.cornerMedium
        case .summary, .centeredActionPanel: LedgerLayout.cornerLarge
        case .sheetChrome: LedgerLayout.cornerMedium
        }
    }
}

private struct LedgerSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.ledgerForceSimplifiedGlass) private var forceSimplified
    let role: LedgerSurfaceRole
    let cornerRadius: CGFloat?
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius ?? role.defaultCornerRadius,
            style: .continuous
        )
        let quality = GlassQualityController.quality(
            reduceTransparency: reduceTransparency,
            forceSimplified: forceSimplified
        )
        content
            .background(shape.fill(quality == .simplified ? LedgerPalette.raisedSurface : surfaceColor))
            .overlay(shape.stroke(LedgerPalette.hairline, lineWidth: borderWidth))
            .shadow(color: tint.opacity(shadowOpacity), radius: shadowRadius, y: 3)
    }

    private var surfaceColor: Color {
        switch role {
        case .functional, .canvas, .floatingControl, .sheetChrome:
            LedgerPalette.surface
        case .summary, .centeredActionPanel:
            LedgerPalette.raisedSurface
        }
    }

    private var borderWidth: CGFloat {
        switch role {
        case .canvas, .summary, .centeredActionPanel: 1
        case .functional, .floatingControl, .sheetChrome: 0.75
        }
    }

    private var shadowOpacity: Double {
        role == .functional || role == .floatingControl ? 0.025 : 0.04
    }

    private var shadowRadius: CGFloat {
        role == .functional || role == .floatingControl ? 5 : 9
    }
}

extension View {
    func ledgerSurface(
        _ role: LedgerSurfaceRole = .functional,
        cornerRadius: CGFloat? = nil,
        tint: Color = LedgerPalette.accent
    ) -> some View {
        modifier(LedgerSurfaceModifier(role: role, cornerRadius: cornerRadius, tint: tint))
    }

    func ledgerContentSurface(cornerRadius: CGFloat = 26, tint: Color = LedgerPalette.accent) -> some View {
        ledgerSurface(.functional, cornerRadius: cornerRadius, tint: tint)
    }

    // Compatibility bridge while feature screens move from decorative glass cards
    // to semantic content surfaces. New interactive chrome should use glassEffect.
    func ledgerGlassCard(cornerRadius: CGFloat = 26, tint: Color = LedgerPalette.accent) -> some View {
        ledgerContentSurface(cornerRadius: cornerRadius, tint: tint)
    }

    func ledgerPageBackground() -> some View {
        background { LedgerPageBackground() }
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
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return Color(uiColor: UIColor { traits in
            let white = traits.userInterfaceStyle == .dark
                ? 0.52 + luminance * 0.38
                : 0.20 + luminance * 0.46
            return UIColor(white: white, alpha: alpha)
        })
    }
}

#if DEBUG
private struct LedgerDesignSystemPreview: View {
    @State private var language = AppLanguage.simplifiedChinese
    @State private var convention = AmountColorConvention.expenseGreenIncomeRed
    @State private var simplifiedGlass = false

    var body: some View {
        ScrollView {
            VStack(spacing: LedgerLayout.sectionSpacing) {
                Picker("preview.language", selection: $language) {
                    ForEach(AppLanguage.allCases.filter { $0 != .system }) {
                        Text($0.title).tag($0)
                    }
                }
                Picker("preview.amountColors", selection: $convention) {
                    ForEach(AmountColorConvention.allCases) { Text($0.title).tag($0) }
                }
                Toggle("preview.simplifiedGlass", isOn: $simplifiedGlass)

                VStack(alignment: .leading, spacing: LedgerLayout.controlSpacing) {
                    Text("preview.summary").font(.headline)
                    Text("¥12,345.67").font(LedgerTypography.largeAmount)
                    HStack {
                        Text("−¥128.00")
                            .foregroundStyle(AmountSemanticStyle.color(for: .expense, convention: convention))
                        Spacer()
                        Text("+¥520.00")
                            .foregroundStyle(AmountSemanticStyle.color(for: .income, convention: convention))
                    }
                    .font(LedgerTypography.amount)
                }
                .padding(LedgerLayout.sectionSpacing)
                .ledgerSurface(.summary)

                Button("preview.primaryAction") {}
                    .frame(maxWidth: .infinity, minHeight: LedgerLayout.primaryButtonHeight)
                    .ledgerSurface(.functional)
                    .buttonStyle(LedgerGlassPressStyle())
            }
            .padding(LedgerLayout.pagePadding)
        }
        .ledgerPageBackground()
        .environment(\.locale, language.locale)
        .environment(\.ledgerForceSimplifiedGlass, simplifiedGlass)
        .preferredColorScheme(.light)
    }
}

#Preview("Design system controls") {
    LedgerDesignSystemPreview()
}
#endif
