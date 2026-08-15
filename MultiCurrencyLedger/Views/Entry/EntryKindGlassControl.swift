import SwiftUI

struct EntryKindGlassControl: View {
    @Binding var selection: TransactionKind
    let validationReset: () -> Void

    private var primaryKinds: [TransactionKind] {
        TransactionKind.allCases.filter { $0 != .adjustment }
    }

    var body: some View {
        HStack(spacing: 0) {
                ForEach(primaryKinds) { kind in
                    Button {
                        validationReset()
                        selection = kind
                    } label: {
                        Text(kind.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(selection == kind ? .white : .primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                selection == kind ? Color.black : .clear
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == kind ? .isSelected : [])
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.black.opacity(0.22), lineWidth: 1) }
    }
}
