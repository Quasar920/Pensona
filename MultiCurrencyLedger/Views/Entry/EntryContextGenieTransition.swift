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
        if reduceMotion || panelFrame.isEmpty || tagFrame.isEmpty {
            content
                .scaleEffect(
                    1 - 0.06 * CGFloat(progress),
                    anchor: tagAnchor
                )
                .opacity(1 - progress)
        } else {
            let shader = ShaderLibrary.entryContextGenieLayer(
                .float2(canvasSize),
                .float4(
                    panelFrame.minX,
                    panelFrame.minY,
                    panelFrame.width,
                    panelFrame.height
                ),
                .float4(
                    tagFrame.minX,
                    tagFrame.minY,
                    tagFrame.width,
                    tagFrame.height
                ),
                .float(progress)
            )
            content
                .compositingGroup()
                .layerEffect(
                    shader,
                    // Declare only the furthest displacement this mapping can
                    // sample. This avoids both edge clipping and the cost of
                    // unconditional full-screen padding.
                    maxSampleOffset: maximumSampleOffset
                )
        }
    }

    private var maximumSampleOffset: CGSize {
        let horizontalEdgeTravel = max(
            abs(panelFrame.minX - tagFrame.minX),
            abs(panelFrame.maxX - tagFrame.maxX)
        )
        let bendTravel = abs(tagFrame.midX - panelFrame.midX) * 0.18
        let verticalEdgeTravel = max(
            abs(panelFrame.minY - tagFrame.minY),
            abs(panelFrame.maxY - tagFrame.maxY)
        )

        return CGSize(
            width: min(canvasSize.width, horizontalEdgeTravel + bendTravel + 2),
            height: min(canvasSize.height, verticalEdgeTravel + 2)
        )
    }

    private var tagAnchor: UnitPoint {
        guard canvasSize.width > 1, canvasSize.height > 1 else {
            return .center
        }
        return UnitPoint(
            x: min(1, max(0, tagFrame.midX / canvasSize.width)),
            y: min(1, max(0, tagFrame.midY / canvasSize.height))
        )
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
