import SwiftUI

struct LedgerBottomBar: View {
    @Binding var selection: LedgerTab
    let addEntry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            tabGroup([.ledger, .assets])
            Button(action: addEntry) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LedgerPalette.accent)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
                    .ledgerSurface(.functional, cornerRadius: 28)
            }
            .buttonStyle(LedgerGlassPressStyle())
            .accessibilityLabel("记一笔")
            .accessibilityIdentifier("root-entry-button")
            tabGroup([.savings, .statistics])
        }
        .padding(.horizontal, LedgerLayout.pagePadding)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func tabGroup(_ tabs: [LedgerTab]) -> some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? LedgerPalette.accent : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LedgerGlassPressStyle())
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("root-tab-\(tab.rawValue)")
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .ledgerSurface(.functional, cornerRadius: 25)
    }
}
