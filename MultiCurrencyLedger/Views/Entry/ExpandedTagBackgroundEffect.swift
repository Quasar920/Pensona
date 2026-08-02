import SwiftUI

/// The stationary backdrop shown while an entry-context tag card is expanded.
/// It keeps the underlying form visually subordinate so the expanded card
/// remains readable while retaining the existing tap-outside-to-cancel path.
struct ExpandedTagBackgroundEffect: View {
    private enum Metrics {
        static let blurMaterialOpacity = 0.72
        static let dimmingOpacity = 0.035
        static let saturation = 0.96
        static let brightness = -0.01
        static let topFeatherHeight: CGFloat = 30
        static let bottomFeatherHeight: CGFloat = 48
        static let reducedTransparencyOpacity = 0.24
    }

    let reduceTransparency: Bool
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            backgroundTreatment
                .saturation(Metrics.saturation)
                .brightness(Metrics.brightness)
                .mask(verticalFeatherMask)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var backgroundTreatment: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground)
                .opacity(Metrics.reducedTransparencyOpacity)
        } else {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(Metrics.blurMaterialOpacity)
                Color.black.opacity(Metrics.dimmingOpacity)
            }
        }
    }

    private var verticalFeatherMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Metrics.topFeatherHeight)

            Rectangle().fill(.white)

            LinearGradient(
                colors: [.white, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Metrics.bottomFeatherHeight)
        }
    }
}
