import SwiftUI

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
    static let amount = Font.system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
    static let largeAmount = Font.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()
}

enum LedgerPalette {
    static let accent = Color(red: 22 / 255, green: 134 / 255, blue: 232 / 255)
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.045, green: 0.055, blue: 0.070, alpha: 1)
            : UIColor(red: 0.955, green: 0.965, blue: 0.975, alpha: 1)
    })
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let separator = Color(uiColor: .separator).opacity(0.24)
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
        ZStack {
            LedgerPalette.background
            GeometryReader { proxy in
                Circle()
                    .fill(LedgerPalette.accent.opacity(0.08))
                    .frame(width: proxy.size.width * 0.9)
                    .blur(radius: 70)
                    .offset(x: proxy.size.width * 0.42, y: -proxy.size.height * 0.30)
                Circle()
                    .fill(Color.cyan.opacity(0.045))
                    .frame(width: proxy.size.width * 0.75)
                    .blur(radius: 80)
                    .offset(x: -proxy.size.width * 0.30, y: proxy.size.height * 0.52)
            }
        }
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
    case centeredActionPanel
    case sheetChrome

    var defaultCornerRadius: CGFloat {
        switch self {
        case .functional: LedgerLayout.cornerMedium
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
        if quality == .simplified {
            content
                .background(shape.fill(Color(uiColor: .secondarySystemBackground)))
                .overlay(shape.stroke(LedgerPalette.separator, lineWidth: 0.75))
        } else {
            content
                .background(shape.fill(material))
                .overlay(shape.stroke(.white.opacity(borderOpacity), lineWidth: 0.75))
                .shadow(color: tint.opacity(shadowOpacity), radius: shadowRadius, y: 4)
        }
    }

    private var material: Material {
        switch role {
        case .functional, .sheetChrome: .regular
        case .summary, .centeredActionPanel: .thick
        }
    }

    private var borderOpacity: Double {
        switch role {
        case .functional, .sheetChrome: 0.30
        case .summary, .centeredActionPanel: 0.40
        }
    }

    private var shadowOpacity: Double {
        role == .functional ? 0.05 : 0.08
    }

    private var shadowRadius: CGFloat {
        role == .functional ? 10 : 16
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
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

#if DEBUG
private struct LedgerDesignSystemPreview: View {
    @State private var appearance = AppAppearance.system
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
                Picker("preview.appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
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
        .preferredColorScheme(appearance.colorScheme)
    }
}

#Preview("Design system controls") {
    LedgerDesignSystemPreview()
}
#endif
