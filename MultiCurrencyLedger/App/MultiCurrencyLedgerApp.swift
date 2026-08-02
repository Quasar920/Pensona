import SwiftData
import SwiftUI

@main
struct MultiCurrencyLedgerApp: App {
    private let modelContainer: ModelContainer
    @State private var preferences = AppPreferences()
    @State private var bootstrapState: BootstrapState = .loading

    private enum BootstrapState: Equatable {
        case loading
        case ready
        case failed
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1"
    }

    init() {
        do {
            modelContainer = try AppModelContainer.make()
        } catch {
            fatalError("无法创建本地数据库：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .environment(preferences)

                if isUITesting, bootstrapState != .loading {
                    Text(bootstrapState == .failed ? "seed failed" : "seed ready")
                        .accessibilityIdentifier(bootstrapState == .failed ? "app-data-seed-failed" : "app-data-ready")
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .allowsHitTesting(false)
                }
            }
            .task {
                do {
                    try LegacyTagRemovalService.removeAll(context: modelContainer.mainContext)
                    try InitialDataService.seedIfNeeded(context: modelContainer.mainContext)
                    try PreviewDataService.seedIfRequested(context: modelContainer.mainContext)
                    if isUITesting {
                        let books = try modelContainer.mainContext.fetch(
                            FetchDescriptor<LedgerBook>(
                                sortBy: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)]
                            )
                        )
                        UserDefaults.standard.set(
                            books.first(where: { !$0.isArchived })?.id.uuidString ?? "",
                            forKey: "selectedBookID"
                        )
                    }
                    _ = AutomationDueService(context: modelContainer.mainContext).generateAllDue()
                    bootstrapState = .ready
                } catch {
                    bootstrapState = .failed
                    assertionFailure("默认分类初始化失败：\(error.localizedDescription)")
                }
                #if !PERFORMANCE_TESTING
                if UserDefaults.standard.bool(forKey: CloudSyncService.enabledKey) {
                    do {
                        let baseCurrencyCode = UserDefaults.standard.string(forKey: "baseCurrencyCode")
                            ?? SupportedCurrency.CNY.rawValue
                        _ = try await CloudSyncService().synchronize(
                            context: modelContainer.mainContext,
                            baseCurrencyCode: baseCurrencyCode
                        )
                    } catch {
                        UserDefaults.standard.set(
                            error.localizedDescription,
                            forKey: CloudSyncService.lastErrorKey
                        )
                    }
                }
                #endif
            }
        }
        .modelContainer(modelContainer)
    }
}
