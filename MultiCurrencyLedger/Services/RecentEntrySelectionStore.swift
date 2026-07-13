import Foundation

struct RecentEntrySelection: Equatable {
    var sourceWalletID: UUID? = nil
    var destinationWalletID: UUID? = nil
    var categoryID: UUID? = nil
    var feeWalletID: UUID? = nil
}

/// Stores only stable identifiers. Every caller must revalidate them against the
/// current book because wallets and categories can be deleted or disabled.
struct RecentEntrySelectionStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selection(bookID: UUID, kind: TransactionKind) -> RecentEntrySelection {
        RecentEntrySelection(
            sourceWalletID: uuid(for: key("source", bookID: bookID, kind: kind)),
            destinationWalletID: uuid(for: key("destination", bookID: bookID, kind: kind)),
            categoryID: uuid(for: key("category", bookID: bookID, kind: kind)),
            feeWalletID: uuid(for: key("fee", bookID: bookID, kind: kind))
        )
    }

    func save(_ selection: RecentEntrySelection, bookID: UUID, kind: TransactionKind) {
        set(selection.sourceWalletID, for: key("source", bookID: bookID, kind: kind))
        set(selection.destinationWalletID, for: key("destination", bookID: bookID, kind: kind))
        set(selection.categoryID, for: key("category", bookID: bookID, kind: kind))
        set(selection.feeWalletID, for: key("fee", bookID: bookID, kind: kind))
    }

    private func key(_ field: String, bookID: UUID, kind: TransactionKind) -> String {
        "entry.recent.\(bookID.uuidString).\(kind.rawValue).\(field)"
    }

    private func uuid(for key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    private func set(_ id: UUID?, for key: String) {
        if let id {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
