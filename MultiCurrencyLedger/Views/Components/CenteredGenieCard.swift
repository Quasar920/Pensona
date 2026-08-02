import SwiftUI
import UIKit

enum CenteredGenieCoordinateSpace {
    static let name = "centered-genie-card"
}

struct CenteredGenieSourceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct CenteredGenieCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

extension View {
    func centeredGenieSourceFrame(id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CenteredGenieSourceFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .global)]
                )
            }
        }
    }
}

struct CenteredGenieCardPresentation: Equatable {
    enum Phase: Equatable {
        case closed
        case preparing
        case opening
        case presented
        case closing
    }

    private(set) var phase: Phase = .closed
    private(set) var sourceFrame: CGRect = .zero
    private(set) var targetFrame: CGRect = .zero
    private(set) var dismissalRequestID: UUID?
    var progress: Double = 1

    var isActive: Bool { phase != .closed }
    var isPresented: Bool { phase == .presented }
    var isTransitioning: Bool { phase == .preparing || phase == .opening || phase == .closing }

    mutating func present(from sourceFrame: CGRect) {
        guard phase == .closed else { return }
        self.sourceFrame = sourceFrame
        targetFrame = .zero
        dismissalRequestID = nil
        progress = 1
        phase = .preparing
    }

    mutating func beginOpening(to targetFrame: CGRect) {
        guard phase == .preparing, !targetFrame.isEmpty else { return }
        self.targetFrame = targetFrame
        phase = .opening
    }

    mutating func finishOpening() {
        guard phase == .opening else { return }
        progress = 0
        phase = .presented
    }

    mutating func beginClosing() {
        guard phase == .presented else { return }
        progress = 0
        phase = .closing
    }

    mutating func requestDismissal() {
        guard phase == .presented else { return }
        dismissalRequestID = UUID()
    }

    mutating func finishClosing() {
        guard phase == .closing else { return }
        phase = .closed
        sourceFrame = .zero
        targetFrame = .zero
        dismissalRequestID = nil
        progress = 1
    }
}

private struct CenteredGenieLayerModifier: ViewModifier {
    let progress: Double
    let panelFrame: CGRect
    let sourceFrame: CGRect
    let canvasSize: CGSize
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion || panelFrame.isEmpty || sourceFrame.isEmpty {
            content
                .scaleEffect(1 - 0.06 * CGFloat(progress), anchor: sourceAnchor)
                .opacity(1 - progress)
        } else {
            content
                .compositingGroup()
                .layerEffect(
                    // The generic entry-tag shader has no outer-edge mask,
                    // which exposes its rectangular compositing texture while
                    // a large card is still travelling. This variant evolves
                    // the panel's 28-point corners into the source capsule on
                    // every intermediate frame.
                    ShaderLibrary.billSearchFilterGenieLayer(
                        .float2(canvasSize),
                        .float4(panelFrame.minX, panelFrame.minY, panelFrame.width, panelFrame.height),
                        .float4(sourceFrame.minX, sourceFrame.minY, sourceFrame.width, sourceFrame.height),
                        .float(progress),
                        .float(28)
                    ),
                    maxSampleOffset: maximumSampleOffset
                )
        }
    }

    private var maximumSampleOffset: CGSize {
        CGSize(
            width: min(canvasSize.width, max(abs(panelFrame.minX - sourceFrame.minX), abs(panelFrame.maxX - sourceFrame.maxX)) + 12),
            height: min(canvasSize.height, max(abs(panelFrame.minY - sourceFrame.minY), abs(panelFrame.maxY - sourceFrame.maxY)) + 12)
        )
    }

    private var sourceAnchor: UnitPoint {
        guard canvasSize.width > 1, canvasSize.height > 1 else { return .center }
        return UnitPoint(
            x: min(1, max(0, sourceFrame.midX / canvasSize.width)),
            y: min(1, max(0, sourceFrame.midY / canvasSize.height))
        )
    }
}

private extension View {
    func centeredGenieLayer(
        progress: Double,
        panelFrame: CGRect,
        sourceFrame: CGRect,
        canvasSize: CGSize,
        reduceMotion: Bool
    ) -> some View {
        modifier(CenteredGenieLayerModifier(
            progress: progress,
            panelFrame: panelFrame,
            sourceFrame: sourceFrame,
            canvasSize: canvasSize,
            reduceMotion: reduceMotion
        ))
    }
}

/// A centered, source-anchored card for compact selection tasks. It deliberately
/// has no page-wide blur or dimming; contrast is carried by the solid card.
struct CenteredGenieCardHost<Card: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var presentation: CenteredGenieCardPresentation
    let maximumWidth: CGFloat
    let onDismissed: () -> Void
    @ViewBuilder let card: () -> Card

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if presentation.isActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginDismissal)
                        .allowsHitTesting(presentation.isPresented)
                        .accessibilityHidden(true)

                    interactiveCard(in: proxy)

                    if presentation.phase == .opening || presentation.phase == .closing {
                        transitionCard(in: proxy)
                    }
                }
            }
            .onPreferenceChange(CenteredGenieCardFramePreferenceKey.self, perform: cardFrameChanged)
        }
        .allowsHitTesting(presentation.isActive)
        .accessibilityHidden(!presentation.isPresented)
        .onChange(of: presentation.dismissalRequestID) { _, requestID in
            guard requestID != nil else { return }
            beginDismissal()
        }
    }

    private func interactiveCard(in proxy: GeometryProxy) -> some View {
        card()
            .frame(width: cardWidth(in: proxy))
            .background {
                GeometryReader { cardProxy in
                    Color.clear.preference(
                        key: CenteredGenieCardFramePreferenceKey.self,
                        value: cardProxy.frame(in: .global)
                    )
                }
            }
            .position(screenCenteredPosition(in: proxy))
            .opacity(presentation.isPresented ? 1 : 0)
            .allowsHitTesting(presentation.isPresented)
            .accessibilityAddTraits(.isModal)
    }

    private func transitionCard(in proxy: GeometryProxy) -> some View {
        let targetFrame = localFrame(presentation.targetFrame, in: proxy)
        let sourceFrame = localFrame(presentation.sourceFrame, in: proxy)
        return card()
            .frame(width: targetFrame.width)
            .position(x: targetFrame.midX, y: targetFrame.midY)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .centeredGenieLayer(
                progress: presentation.progress,
                panelFrame: targetFrame,
                sourceFrame: sourceFrame,
                canvasSize: proxy.size,
                reduceMotion: reduceMotion
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func cardWidth(in proxy: GeometryProxy) -> CGFloat {
        min(maximumWidth, max(260, proxy.size.width - 36))
    }

    private func localFrame(_ globalFrame: CGRect, in proxy: GeometryProxy) -> CGRect {
        let hostFrame = proxy.frame(in: .global)
        return CGRect(
            x: globalFrame.minX - hostFrame.minX,
            y: globalFrame.minY - hostFrame.minY,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }

    /// An overlay placed inside a navigation stack otherwise centers in the
    /// content region below the navigation bar. These cards are intentionally
    /// centered in the full device viewport instead.
    private func screenCenteredPosition(in proxy: GeometryProxy) -> CGPoint {
        let hostFrame = proxy.frame(in: .global)
        let screenBounds = UIScreen.main.bounds
        return CGPoint(
            x: screenBounds.midX - hostFrame.minX,
            y: screenBounds.midY - hostFrame.minY
        )
    }

    private func cardFrameChanged(_ frame: CGRect) {
        guard presentation.phase == .preparing else { return }
        presentation.beginOpening(to: frame)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(17))
            guard presentation.phase == .opening else { return }
            withAnimation(transitionAnimation) {
                presentation.progress = 0
            } completion: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    presentation.finishOpening()
                }
            }
        }
    }

    private func beginDismissal() {
        guard presentation.isPresented else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation.beginClosing()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(17))
            guard presentation.phase == .closing else { return }
            withAnimation(transitionAnimation) {
                presentation.progress = 1
            } completion: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    presentation.finishClosing()
                }
                onDismissed()
            }
        }
    }

    private var transitionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.20)
            : .timingCurve(0.22, 0.72, 0.18, 1, duration: 0.62)
    }
}

struct CenteredGenieCardSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .background(surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.62), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.36 : 0.18), radius: 24, y: 12)
    }

    private var surface: Color {
        colorScheme == .dark ? Color(white: 0.11).opacity(0.985) : Color.white.opacity(0.985)
    }
}
