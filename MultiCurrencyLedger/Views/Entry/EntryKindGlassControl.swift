import SwiftUI

struct EntryKindGlassControl: View {
    @Binding var selection: TransactionKind
    let validationReset: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(TransactionKind.allCases) { kind in
                            Button {
                                validationReset()
                                selection = kind
                            } label: {
                                Text(kind.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(selection == kind ? LedgerPalette.accent : .secondary)
                                    .padding(.horizontal, 16)
                                    .frame(minWidth: 72, minHeight: LedgerLayout.minimumHitSize)
                                    .background(
                                        selection == kind ? LedgerPalette.accent.opacity(0.10) : .clear,
                                        in: Capsule()
                                    )
                                    .overlay(Capsule().stroke(
                                        selection == kind ? LedgerPalette.accent.opacity(0.64) : .clear
                                    ))
                            }
                            .buttonStyle(LedgerGlassPressStyle())
                            .glassEffect(.regular.interactive(), in: Capsule())
                            .accessibilityAddTraits(selection == kind ? .isSelected : [])
                            .id(kind.id)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selection.id, anchor: .center) }
            .onChange(of: selection) { _, kind in
                withAnimation(LedgerMotion.responsive) { proxy.scrollTo(kind.id, anchor: .center) }
            }
        }
    }
}
