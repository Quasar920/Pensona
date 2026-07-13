import SwiftData
import SwiftUI

@main
struct MultiCurrencyLedgerApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try AppModelContainer.make()
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
                        _ = AutomationDueService(context: modelContainer.mainContext).generateAllDue()
                    } catch {
                        assertionFailure("默认分类初始化失败：\(error.localizedDescription)")
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
