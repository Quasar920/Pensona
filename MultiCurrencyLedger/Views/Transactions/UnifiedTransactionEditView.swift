import SwiftUI

/// Editing intentionally reuses the same entry surface, validation, calculation,
/// and save gate as creation. The original transaction and book identity are
/// retained by `EntrySessionState.Mode.edit`.
struct TransactionEditView: View {
    let transaction: LedgerTransaction
    let onSaved: () -> Void

    var body: some View {
        EntryView(editing: transaction, onSaved: onSaved)
    }
}
