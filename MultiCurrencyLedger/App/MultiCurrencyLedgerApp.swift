import SwiftData
import SwiftUI

@main
struct MultiCurrencyLedgerApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                LedgerBook.self,
                Account.self,
                CurrencyWallet.self,
                LedgerCategory.self,
                LedgerTransaction.self,
                ExchangeRate.self,
                MonthlyBudget.self
            ])
            modelContainer = try ModelContainer(for: schema)
        } catch {
            fatalError("无法创建本地数据库：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    do {
                        try InitialDataService.seedIfNeeded(context: modelContainer.mainContext)
                        try PreviewDataService.seedIfRequested(context: modelContainer.mainContext)
                    } catch {
                        assertionFailure("默认分类初始化失败：\(error.localizedDescription)")
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
