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
    }

    @ViewBuilder
    private func shell(route: RootEntryPresentation, in proxy: GeometryProxy) -> some View {
        let compact: CGFloat = 56
        let expandedWidth = proxy.size.width
        // This container ignores the safe area, so use the window inset to
        // locate the Dynamic Island rather than letting the sheet overlap it.
        // One point is three physical pixels on the connected iPhone.
        let safeAreaTop = max(proxy.safeAreaInsets.top, activeWindowSafeAreaTop)
        let dynamicIslandBottom = max(48, safeAreaTop - 10)
        let topClearance = dynamicIslandBottom + 1
        let bottomClearance: CGFloat = 0
        let expandedHeight = max(
            compact,
            proxy.size.height - topClearance - bottomClearance
        )
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color(red: 247 / 255, green: 245 / 255, blue: 239 / 255))
                .opacity(contentVisible ? 1 : 0)
            if contentVisible {
                entryContent(route)
                    // The kind selector now occupies the sheet cap directly
                    // below the drag handle instead of leaving it empty.
                    .padding(.top, 10)
                    .modifier(EntryPreviewDynamicTypeModifier())
                    .transition(.opacity)
            }
            Button(action: {}) {
                Capsule()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
                    .padding(.top, 11)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .opacity(contentVisible ? 1 : 0)
                .gesture(topDragGesture)
                .accessibilityLabel("拖拽关闭记账")
                .accessibilityIdentifier("receipt-entry-drag-handle")
        }
        .frame(
            width: shellExpanded ? expandedWidth : compact,
            height: shellExpanded ? expandedHeight : compact
        )
        .clipShape(RoundedRectangle(
            cornerRadius: shellExpanded ? 30 : compact / 2,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: shellExpanded ? 30 : compact / 2,
                style: .continuous
            )
                .stroke(.white.opacity(shellExpanded ? 0.22 : 0.46), lineWidth: 0.75)
        }
        .offset(y: shellExpanded ? max(0, dragOffset) : -12)
        .padding(.bottom, bottomClearance)
        .accessibilityIdentifier("receipt-entry-sheet")
        .animation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.physical, value: shellExpanded)
        .transaction { transaction in
            if dragOffset > 0 { transaction.animation = nil }
        }
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

    private var topDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragOffset = max(0, value.translation.height)
                }
            }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 220 {
                    requestClose()
                } else {
                    withAnimation(LedgerMotion.responsive) { dragOffset = 0 }
                }
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
        contentVisible = false
        await Task.yield()
        withAnimation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.physical) {
            shellExpanded = true
        }
        if !reduceMotion {
            try? await Task.sleep(for: .milliseconds(190))
        }
        guard !Task.isCancelled else { return }
        withAnimation(LedgerMotion.reduced) { contentVisible = true }
    }

    private func requestClose() {
        collapse()
    }

    private func collapse(saved: Bool = false) {
        withAnimation(LedgerMotion.reduced) { contentVisible = false }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(110)) }
            withAnimation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.physical) {
                shellExpanded = false
                dragOffset = 0
            }
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(210)) }
            presentation.finishDismissal()
            if saved { onEntrySaved() }
        }
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
