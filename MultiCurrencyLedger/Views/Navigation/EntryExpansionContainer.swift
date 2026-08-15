import SwiftUI

struct EntryExpansionContainer: View {
    @Bindable var presentation: RootPresentationState
    let onEntrySaved: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shellExpanded = false
    @State private var contentVisible = false
    @State private var dragOffset: CGFloat = 0
    @State private var hasUnsavedChanges = false

    init(presentation: RootPresentationState, onEntrySaved: @escaping () -> Void = {}) {
        self.presentation = presentation
        self.onEntrySaved = onEntrySaved
    }

    var body: some View {
        GeometryReader { proxy in
            if let route = presentation.entry {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(shellExpanded ? backdropOpacity(in: proxy) : 0)
                        .ignoresSafeArea()
                        .onTapGesture(perform: requestClose)
                        .accessibilityIdentifier("receipt-entry-backdrop")

                    shell(route: route, in: proxy)
                }
                .task(id: route.id) { await expand() }
            }
        }
        .ignoresSafeArea(.container, edges: .all)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func shell(route: RootEntryPresentation, in proxy: GeometryProxy) -> some View {
        let expandedWidth = proxy.size.width
        // This container ignores the safe area, so use the window inset to
        // locate the Dynamic Island rather than letting the sheet overlap it.
        // One point is three physical pixels on the connected iPhone.
        let safeAreaTop = max(proxy.safeAreaInsets.top, activeWindowSafeAreaTop)
        let dynamicIslandBottom = max(48, safeAreaTop - 10)
        let topClearance = dynamicIslandBottom + 1
        let bottomClearance: CGFloat = 0
        let expandedHeight = max(
            56,
            proxy.size.height - topClearance - bottomClearance
        )
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color(red: 247 / 255, green: 245 / 255, blue: 239 / 255))
                .opacity(contentVisible ? 1 : 0)
            if contentVisible {
                entryContent(route)
                    // Keep the transaction-kind selector below the drag
                    // handle's hit area. Otherwise the handle sits above the
                    // top row and intercepts taps on 收入 / 转账 / 换汇.
                    .padding(.top, 44)
                    .modifier(EntryPreviewDynamicTypeModifier())
                    .transition(.opacity)
            }
            Button(action: {}) {
                Capsule()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 38, height: 5)
                    .padding(.top, 11)
                    // The gesture hit target must end before the editor's
                    // first row begins.
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .opacity(contentVisible ? 1 : 0)
                .accessibilityLabel("拖拽关闭记账")
                .accessibilityIdentifier("receipt-entry-drag-handle")
                // Limit sheet-dismiss dragging to its handle. Applying this
                // as a high-priority gesture to the whole sheet swallowed
                // taps on the transaction-kind selector and option rows.
                .highPriorityGesture(topDragGesture(in: proxy))
        }
        .frame(width: expandedWidth, height: expandedHeight)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.75)
        }
        .offset(y: shellExpanded ? dragOffset : proxy.size.height + 80)
        .padding(.bottom, bottomClearance)
        .accessibilityIdentifier("receipt-entry-sheet")
    }

    @ViewBuilder
    private func entryContent(_ route: RootEntryPresentation) -> some View {
        switch route.mode {
        case .new:
            EntryView(
                hasUnsavedChanges: $hasUnsavedChanges,
                requestDismiss: requestClose,
                requestSaveDismiss: { collapse(saved: true) }
            )
        case let .external(draft):
            EntryView(
                seed: draft,
                dismissAfterSave: true,
                resetSeedDate: false,
                presentationTitle: AppLocalization.string("确认外部记账"),
                hasUnsavedChanges: $hasUnsavedChanges,
                requestDismiss: requestClose,
                requestSaveDismiss: { collapse(saved: true) }
            )
        }
    }

    private func topDragGesture(in proxy: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragOffset = interactiveDragOffset(for: value.translation.height)
                }
            }
            .onEnded { value in
                if dragOffset > 170 || value.predictedEndTranslation.height * 0.78 > 320 {
                    dismissFromDrag(in: proxy)
                } else {
                    withAnimation(LedgerMotion.responsive) { dragOffset = 0 }
                }
            }
    }

    private func interactiveDragOffset(for translation: CGFloat) -> CGFloat {
        translation >= 0 ? translation * 0.78 : translation * 0.10
    }

    private func dismissFromDrag(in proxy: GeometryProxy) {
        let dismissalDistance = max(proxy.size.height + 80, dragOffset)
        withAnimation(reduceMotion ? LedgerMotion.reduced : sheetDismissAnimation) {
            dragOffset = dismissalDistance
        }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(300)) }
            contentVisible = false
            shellExpanded = false
            dragOffset = 0
            presentation.finishDismissal()
        }
    }

    private func backdropOpacity(in proxy: GeometryProxy) -> Double {
        guard proxy.size.height > 0 else { return 0.30 }
        let progress = min(1, max(0, dragOffset / (proxy.size.height * 0.55)))
        return 0.30 * (1 - progress)
    }

    private var activeWindowSafeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }

    private func expand() async {
        hasUnsavedChanges = false
        dragOffset = 0
        shellExpanded = false
        contentVisible = true
        await Task.yield()
        withAnimation(reduceMotion ? LedgerMotion.reduced : sheetPresentationAnimation) {
            shellExpanded = true
        }
    }

    private func requestClose() {
        collapse()
    }

    private func collapse(saved: Bool = false) {
        withAnimation(reduceMotion ? LedgerMotion.reduced : sheetDismissAnimation) {
            dragOffset = dismissalTravelDistance
        }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(300)) }
            contentVisible = false
            shellExpanded = false
            dragOffset = 0
            presentation.finishDismissal()
            if saved { onEntrySaved() }
        }
    }

    private var sheetPresentationAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.90)
    }

    private var sheetDismissAnimation: Animation {
        .timingCurve(0.20, 0.80, 0.20, 1, duration: 0.30)
    }

    private var dismissalTravelDistance: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds.height ?? 1_000
    }
}

private struct EntryPreviewDynamicTypeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ENTRY_PREVIEW_ACCESSIBILITY_TEXT"] == "1" {
            content.environment(\.dynamicTypeSize, .accessibility3)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
