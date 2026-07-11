import Foundation

struct RecognitionAccountOption: Codable, Equatable {
    let walletID: UUID
    let accountName: String
    let accountNote: String?
    let currencyCode: String
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
    func makeContext(book: LedgerBook, categories: [LedgerCategory]) -> RecognitionRequestContext {
        let accounts = book.accounts
            .flatMap { account in
                account.enabledWallets.map { wallet in
                    RecognitionAccountOption(
                        walletID: wallet.id,
                        accountName: account.name,
                        accountNote: account.note,
                        currencyCode: wallet.currencyCode
                    )
                }
            }
            .sorted {
                ($0.accountName, $0.currencyCode) < ($1.accountName, $1.currencyCode)
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
