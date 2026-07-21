import SwiftUI

struct EntryGlassKeypad: View {
    @Binding var amountText: String
    let currencyCode: String
    let resetID: UUID
    let showsNextEntry: Bool
    let isSaving: Bool
    let nextEntry: () -> Void
    let complete: () -> Void

    @State private var calculation = EntryCalculationState()

    private var fractionDigits: Int { SupportedCurrency.fractionDigits(for: currencyCode) }

    var body: some View {
        VStack(spacing: 6) {
            if let expression = calculation.expression {
                Text(expression)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 6)
            }
            Grid(horizontalSpacing: 7, verticalSpacing: 7) {
                GridRow {
                    key("7"); key("8"); key("9"); operation(.add); operation(.subtract)
                }
                GridRow {
                    key("4"); key("5"); key("6"); operation(.multiply); operation(.divide)
                }
                GridRow {
                    key("1"); key("2"); key("3")
                    actionButton(showsNextEntry ? "下一笔" : "清空", primary: false) {
                        if showsNextEntry { nextEntry() }
                        else { calculation.clear(displayText: &amountText) }
                    }
                    .gridCellColumns(2)
                    .disabled(isSaving)
                }
                GridRow {
                    key("."); key("0"); deleteKey
                    actionButton("完成", primary: true, action: complete)
                        .gridCellColumns(2)
                        .disabled(isSaving)
                }
            }
        }
        .padding(10)
        .ledgerSurface(.functional, cornerRadius: 22)
        .onChange(of: resetID) { _, _ in calculation.reset() }
        .onChange(of: amountText) { _, newValue in
            if newValue.isEmpty { calculation.reset() }
        }
    }

    private func key(_ label: String) -> some View {
        Button {
            calculation.append(label, displayText: &amountText, fractionDigits: fractionDigits)
        } label: {
            Text(label)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(EntryKeyStyle())
    }

    private func operation(_ operation: EntryCalculationOperator) -> some View {
        Button {
            calculation.begin(operation, displayText: amountText)
        } label: {
            Text(operation.rawValue)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(LedgerPalette.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(EntryKeyStyle())
        .accessibilityLabel(operation.accessibilityLabel)
    }

    private var deleteKey: some View {
        Button {
            calculation.delete(displayText: &amountText, fractionDigits: fractionDigits)
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(EntryKeyStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.7).onEnded { _ in
            calculation.clear(displayText: &amountText)
        })
        .accessibilityLabel("删除；长按清空")
    }

    private func actionButton(
        _ title: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(EntryKeyActionStyle(primary: primary))
    }
}

private struct EntryKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(LedgerMotion.press(isPressed: configuration.isPressed), value: configuration.isPressed)
    }
}

private struct EntryKeyActionStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? Color.primary : LedgerPalette.accent)
            .background(
                primary ? LedgerPalette.accent.opacity(0.22) : Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                primary ? LedgerPalette.accent.opacity(0.48) : .clear
            ))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(LedgerMotion.press(isPressed: configuration.isPressed), value: configuration.isPressed)
    }
}

private extension EntryCalculationOperator {
    var accessibilityLabel: String {
        switch self {
        case .add: AppLocalization.string( "加")
        case .subtract: AppLocalization.string( "减")
        case .multiply: AppLocalization.string( "乘")
        case .divide: AppLocalization.string( "除")
        }
    }
}
