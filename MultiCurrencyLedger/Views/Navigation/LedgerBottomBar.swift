import SwiftUI

struct LedgerBottomBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: LedgerTab
    let addEntry: () -> Void
    @State private var tabFrames: [LedgerTab: CGRect] = [:]

    var body: some View {
        navigationRail
        .padding(.horizontal, LedgerLayout.pagePadding)
        .padding(.bottom, 7)
    }

    private var navigationRail: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                tabButton(.ledger)
                tabButton(.assets)
            }
            .frame(maxWidth: .infinity)

            entryButton

            HStack(spacing: 2) {
                tabButton(.savings)
                tabButton(.statistics)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(LedgerPalette.surface, in: Capsule())
        .overlay(Capsule().stroke(LedgerPalette.hairline, lineWidth: 1))
        .shadow(color: LedgerPalette.ink.opacity(0.04), radius: 8, y: 3)
        .coordinateSpace(name: Self.coordinateSpaceName)
        .onPreferenceChange(LedgerTabFramePreferenceKey.self) { tabFrames = $0 }
        .simultaneousGesture(slideGesture)
        .accessibilityElement(children: .contain)
    }

    private var entryButton: some View {
        Button(action: addEntry) {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .semibold))
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

    private func tabButton(_ tab: LedgerTab) -> some View {
        let isSelected = selection == tab
        return Button {
            select(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.selectedSymbolName : tab.symbolName)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 22, height: 22)
                Text(tab.title)
                    .font(.caption2.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(LedgerPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(isSelected ? LedgerPalette.selectionFill : .clear, in: Capsule())
            .contentShape(Capsule())
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: LedgerTabFramePreferenceKey.self,
                        value: [tab: proxy.frame(in: .named(Self.coordinateSpaceName))]
                    )
                }
            }
        }
        .buttonStyle(LedgerGlassPressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "已选择" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("root-tab-\(tab.rawValue)")
    }

    private var slideGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance > 4,
                      let hovered = tabFrames.first(where: { $0.value.contains(value.location) })?.key else {
                    return
                }
                select(hovered)
            }
    }

    private func select(_ tab: LedgerTab) {
        guard selection != tab else { return }
        HapticFeedbackService().selection()
        withAnimation(reduceMotion ? LedgerMotion.reduced : .spring(response: 0.34, dampingFraction: 0.82)) {
            selection = tab
        }
    }

    private static let coordinateSpaceName = "ledger-bottom-navigation"
}

private struct LedgerTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [LedgerTab: CGRect] = [:]

    static func reduce(
        value: inout [LedgerTab: CGRect],
        nextValue: () -> [LedgerTab: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
