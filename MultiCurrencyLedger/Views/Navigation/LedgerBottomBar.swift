import SwiftUI

/// The root navigation is intentionally a four-item control. The recording
/// action stays centered so the navigation keeps a stable, equal-width rhythm.
struct LedgerBottomBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selection: LedgerTab
    let addEntry: () -> Void
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.ledger)
            tabButton(.assets)
            entryButton
            tabButton(.savings)
            tabButton(.statistics)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background {
            let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
            if reduceTransparency {
                shape.fill(LedgerPalette.surface)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(LedgerPalette.hairline.opacity(0.7), lineWidth: 0.75)
        }
        .shadow(color: LedgerPalette.ink.opacity(0.045), radius: 10, y: 3)
        .padding(.horizontal, 14)
        .padding(.bottom, 7)
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: LedgerTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            HapticFeedbackService().selection()
            withAnimation(selectionAnimation) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        selectionCapsule
                            .matchedGeometryEffect(id: "root-tab-selection", in: selectionNamespace)
                    }

                    Image(systemName: tab.symbolName)
                        .font(.system(size: 19, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isSelected ? LedgerPalette.ink : .secondary)
                        .scaleEffect(reduceMotion || !isSelected ? 1 : 0.98)
                }
                .frame(width: 36, height: 30)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? LedgerPalette.ink : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "已选择" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("root-tab-\(tab.rawValue)")
    }

    private var entryButton: some View {
        Button(action: addEntry) {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(LedgerPalette.invertedInk)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
                .background(LedgerPalette.ink, in: Circle())
                .overlay(Circle().stroke(LedgerPalette.hairline, lineWidth: 1))
                .shadow(color: LedgerPalette.ink.opacity(0.10), radius: 8, y: 3)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .accessibilityLabel("记一笔")
        .accessibilityHint("新建一笔交易")
        .accessibilityIdentifier("root-entry-button")
    }

    @ViewBuilder
    private var selectionCapsule: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        if reduceTransparency {
            shape.fill(LedgerPalette.selectionFill)
        } else {
            shape
                .fill(.thinMaterial)
                .overlay(shape.fill(Color.white.opacity(0.12)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.42), lineWidth: 0.5))
        }
    }

    private var selectionAnimation: Animation {
        reduceMotion ? LedgerMotion.reduced : .spring(response: 0.34, dampingFraction: 0.82)
    }
}
