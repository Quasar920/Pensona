import SwiftUI

enum EntryKeypadInputMode: Equatable {
    case amount
    case wholeNumber
}

struct EntryGlassKeypad: View {
    @Binding var amountText: String
    let currencyCode: String
    let resetID: UUID
    let inputMode: EntryKeypadInputMode
    let showsNextEntry: Bool
    let isSaving: Bool
    let canComplete: Bool
    let nextEntry: () -> Void
    let complete: () -> Void

    @State private var calculation = EntryCalculationState()
    @State private var hasEnteredValueSinceReset = false

    private var fractionDigits: Int {
        inputMode == .wholeNumber
            ? 0
            : SupportedCurrency.fractionDigits(for: currencyCode)
    }

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
                    operation(.add); operation(.subtract); operation(.multiply); operation(.divide)
                }
                GridRow {
                    key("7"); key("8"); key("9"); deleteKey
                }
                GridRow {
                    key("4"); key("5"); key("6"); key(".")
                }
                GridRow {
                    key("1"); key("2"); key("3"); key("0")
                }
                GridRow {
                    actionButton(
                        showsNextEntry
                            ? (AppLocalization.locale.language.languageCode?.identifier == "en" ? "Next" : AppLocalization.string("下一笔"))
                            : AppLocalization.string("清空"),
                        primary: false
                    ) {
                        if showsNextEntry { nextEntry() }
                        else { calculation.clear(displayText: &amountText) }
                    }
                    .gridCellColumns(2)
                    .disabled(isSaving)
                    actionButton(AppLocalization.string("完成"), primary: true, action: complete)
                        .gridCellColumns(2)
                        .disabled(isSaving || !canComplete)
                }
            }
        }
        .padding(10)
        .onChange(of: resetID) { _, _ in
            calculation.reset()
            hasEnteredValueSinceReset = false
        }
        .onChange(of: amountText) { _, newValue in
            if newValue.isEmpty { calculation.reset() }
        }
    }

    private func key(_ label: String) -> some View {
        Button {
            if inputMode == .wholeNumber, !hasEnteredValueSinceReset {
                amountText = ""
                calculation.reset()
            }
            calculation.append(label, displayText: &amountText, fractionDigits: fractionDigits)
            hasEnteredValueSinceReset = true
        } label: {
            Text(label)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(EntryKeyStyle())
        .disabled(inputMode == .wholeNumber && label == ".")
        .opacity(inputMode == .wholeNumber && label == "." ? 0.32 : 1)
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
        .disabled(inputMode == .wholeNumber)
        .opacity(inputMode == .wholeNumber ? 0.32 : 1)
        .accessibilityLabel(operation.accessibilityLabel)
    }

    private var deleteKey: some View {
        Button {
            hasEnteredValueSinceReset = true
            calculation.delete(displayText: &amountText, fractionDigits: fractionDigits)
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(EntryKeyStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.7).onEnded { _ in
            hasEnteredValueSinceReset = true
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
