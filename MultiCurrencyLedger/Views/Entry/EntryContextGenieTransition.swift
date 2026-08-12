import SwiftUI

enum EntryContextCoordinateSpace {
    static let name = "entry-context-composer"
}

struct EntryContextTagFramePreferenceKey: PreferenceKey {
    static var defaultValue: [EntryContextOverlayKind: CGRect] = [:]

    static func reduce(
        value: inout [EntryContextOverlayKind: CGRect],
        nextValue: () -> [EntryContextOverlayKind: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct EntryContextPanelFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}

private struct EntryContextGenieLayerModifier: ViewModifier {
    let progress: Double
    let panelFrame: CGRect
    let tagFrame: CGRect
    let canvasSize: CGSize
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .scaleEffect(1 - 0.03 * CGFloat(progress))
                .opacity(1 - progress)
        } else {
            content
                .scaleEffect(1 - 0.06 * CGFloat(progress))
                .offset(y: 18 * CGFloat(progress))
                .opacity(1 - progress)
        }
    }
}

extension View {
    @ViewBuilder
    func entryContextGenieLayer(
        progress: Double,
        panelFrame: CGRect,
        tagFrame: CGRect,
        canvasSize: CGSize,
        reduceMotion: Bool
    ) -> some View {
        modifier(EntryContextGenieLayerModifier(
            progress: progress,
            panelFrame: panelFrame,
            tagFrame: tagFrame,
            canvasSize: canvasSize,
            reduceMotion: reduceMotion
        ))
    }
}

struct EntryContextSourceTagOverlay: View {
    let kind: EntryContextOverlayKind
    let visual: EntryContextTagVisual
    let frame: CGRect
    let isInteractive: Bool
    let cancel: () -> Void

    var body: some View {
        Button(action: cancel) {
            EntryContextTagLabel(visual: visual)
                .frame(width: frame.width, height: frame.height)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(isInteractive)
        .accessibilityHidden(!isInteractive)
        .accessibilityLabel(visual.title)
        .accessibilityHint("再次轻点关闭并取消修改")
        .accessibilityIdentifier("entry-context-source-tag-\(kind.rawValue)")
    }
}

/// Legacy backdrop layer retained for the previous entry-context rendering
/// path. The active tag presentation uses `ExpandedTagBackgroundEffect`.
struct EntryContextBackdropLayer: View {
    static let featherHeight: CGFloat = 44

    let progress: Double
    let reduceTransparency: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop
                .mask(backdropMask)

            keypadSurfaceWash
                .frame(height: Self.featherHeight)
                .opacity(progress)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var backdrop: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground)
                .opacity(0.72 * progress)
        } else {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(progress)
                Color.black.opacity(0.18 * progress)
            }
        }
    }

    private var backdropMask: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white)
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.94), location: 0.34),
                    .init(color: .white.opacity(0.55), location: 0.72),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.featherHeight)
        }
    }

    private var keypadSurfaceWash: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(uiColor: .systemBackground).opacity(0.16), location: 0.42),
                    .init(color: Color(uiColor: .systemBackground).opacity(0.72), location: 0.78),
                    .init(color: Color(uiColor: .systemBackground), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [.clear, Color.primary.opacity(0.055)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
