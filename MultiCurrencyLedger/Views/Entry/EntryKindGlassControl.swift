import SwiftUI

struct EntryKindGlassControl: View {
    @Binding var selection: TransactionKind
    let validationReset: () -> Void

    private var primaryKinds: [TransactionKind] {
        TransactionKind.allCases.filter { $0 != .adjustment }
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(primaryKinds) { kind in
                    Button {
                        validationReset()
                        selection = kind
                    } label: {
                        Text(kind.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == kind ? LedgerPalette.accent : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 42)
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
                }
            }
        }
        .padding(.vertical, 1)
    }
}
