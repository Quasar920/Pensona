import SwiftUI

struct EntryExpansionContainer: View {
    @Bindable var presentation: RootPresentationState
    let onEntrySaved: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shellExpanded = false
    @State private var contentVisible = false
    @State private var dragOffset: CGFloat = 0
    @State private var hasUnsavedChanges = false
    @State private var showingDiscardConfirmation = false

    init(presentation: RootPresentationState, onEntrySaved: @escaping () -> Void = {}) {
        self.presentation = presentation
        self.onEntrySaved = onEntrySaved
    }

    var body: some View {
        GeometryReader { proxy in
            if let route = presentation.entry {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(shellExpanded ? 0.16 : 0)
                        .ignoresSafeArea()
                        .onTapGesture(perform: requestClose)

                    shell(route: route, in: proxy)
                }
                .task(id: route.id) { await expand() }
                .confirmationDialog(
                    "放弃这笔未保存的记账？",
                    isPresented: $showingDiscardConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("放弃", role: .destructive) { collapse() }
                    Button("继续编辑", role: .cancel) {}
                }
            }
        }
        .ignoresSafeArea(.container, edges: .all)
    }

    @ViewBuilder
    private func shell(route: RootEntryPresentation, in proxy: GeometryProxy) -> some View {
        let compact: CGFloat = 56
        let expandedWidth = proxy.size.width
        let expandedHeight = proxy.size.height
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).opacity(contentVisible ? 1 : 0)
            if contentVisible {
                entryContent(route)
                    .modifier(EntryPreviewDynamicTypeModifier())
                    .transition(.opacity)
            }
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 38, height: 5)
                .padding(.top, proxy.safeAreaInsets.top + 10)
                .opacity(contentVisible ? 1 : 0)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .top)
                .contentShape(Rectangle())
                .gesture(topDragGesture)
        }
        .frame(
            width: shellExpanded ? expandedWidth : compact,
            height: shellExpanded ? expandedHeight : compact
        )
        .clipShape(RoundedRectangle(
            cornerRadius: shellExpanded ? LedgerLayout.cornerLarge : compact / 2,
            style: .continuous
        ))
        .ledgerSurface(.sheetChrome, cornerRadius: shellExpanded ? LedgerLayout.cornerLarge : compact / 2)
        .offset(y: shellExpanded ? max(0, dragOffset) : -12)
        .padding(.bottom, shellExpanded ? 0 : 6)
        .animation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.physical, value: shellExpanded)
        .animation(LedgerMotion.responsive, value: dragOffset)
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
        DragGesture(minimumDistance: 4)
            .onChanged { value in dragOffset = max(0, value.translation.height) }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 220 {
                    requestClose()
                } else {
                    withAnimation(LedgerMotion.responsive) { dragOffset = 0 }
                }
            }
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
        if hasUnsavedChanges {
            withAnimation(LedgerMotion.responsive) { dragOffset = 0 }
            showingDiscardConfirmation = true
        } else {
            collapse()
        }
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
