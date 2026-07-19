import Foundation

struct RecognitionAccountOption: Codable, Equatable {
    let walletID: UUID
    let accountName: String
    let accountNote: String?
    let accountLastFour: String?
    let currencyCode: String

    init(
        walletID: UUID,
        accountName: String,
        accountNote: String?,
        accountLastFour: String? = nil,
        currencyCode: String
    ) {
        self.walletID = walletID
        self.accountName = accountName
        self.accountNote = accountNote
        self.accountLastFour = accountLastFour
        self.currencyCode = currencyCode
    }
}

struct RecognitionCategoryOption: Codable, Equatable {
    let name: String
    let type: CategoryKind
}

struct RecognitionRequestContext: Codable, Equatable {
    let bookID: UUID
    let bookName: String
    let accounts: [RecognitionAccountOption]
    let categories: [RecognitionCategoryOption]
}

struct RecognitionContextBuilder {
    private let cardIdentityStore: AccountCardIdentityStore

    init(cardIdentityStore: AccountCardIdentityStore = AccountCardIdentityStore()) {
        self.cardIdentityStore = cardIdentityStore
    }

    func makeContext(book: LedgerBook, categories: [LedgerCategory]) -> RecognitionRequestContext {
        let accounts = book.accounts
            .filter { !$0.isArchived }
            .flatMap { account in
                account.enabledWallets.map { wallet in
                    RecognitionAccountOption(
                        walletID: wallet.id,
                        accountName: account.name,
                        accountNote: account.note,
                        accountLastFour: account.type.supportsCardLastFour
                            ? cardIdentityStore.lastFour(for: account.id)
                            : nil,
                        currencyCode: wallet.currencyCode
                    )
                }
            }
            .sorted {
                ($0.accountName, $0.currencyCode, $0.walletID.uuidString)
                    < ($1.accountName, $1.currencyCode, $1.walletID.uuidString)
            }
        let categoryOptions = categories
            .sorted { ($0.typeRawValue, $0.sortOrder, $0.name) < ($1.typeRawValue, $1.sortOrder, $1.name) }
            .map { RecognitionCategoryOption(name: $0.name, type: $0.type) }
        return RecognitionRequestContext(
            bookID: book.id,
            bookName: book.name,
            accounts: accounts,
            categories: categoryOptions
        )
    }
}
