import Foundation
import Observation
import SwiftData

enum AppLaunchState: Equatable {
    case initializing
    case needsOnboarding
    case ready
    case recoverableFailure(AppLaunchFailure)
}

struct AppLaunchFailure: Equatable {
    enum Stage: Equatable {
        case openingDatabase
        case initializingData
    }

    let stage: Stage
    let message: String
    let snapshots: [MigrationStoreSnapshot]
}

@MainActor
@Observable
final class AppLaunchCoordinator {
    typealias ContainerFactory = @MainActor () throws -> ModelContainer
    typealias ContainerInitializer = @MainActor (ModelContainer) throws -> AppLaunchState

    static let onboardingCompletedKey = "hasCompletedOnboarding"

    private(set) var state: AppLaunchState = .initializing
    private(set) var modelContainer: ModelContainer?

    let isUITesting: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeContainer: ContainerFactory
    @ObservationIgnored private let initializeContainer: ContainerInitializer
    @ObservationIgnored private var hasStarted = false

    init(
        isUITesting: Bool = ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1",
        defaults: UserDefaults = .standard,
        makeContainer: @escaping ContainerFactory = { try AppModelContainer.make() },
        initializeContainer: ContainerInitializer? = nil
    ) {
        self.isUITesting = isUITesting
        self.defaults = defaults
        self.makeContainer = makeContainer
        self.initializeContainer = initializeContainer ?? { container in
            try Self.initialize(
                container: container,
                isUITesting: isUITesting,
                defaults: defaults
            )
        }
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        bootstrap()
    }

    func retry() {
        state = .initializing
        bootstrap()
    }

    func retryUsing(_ snapshot: MigrationStoreSnapshot) {
        guard modelContainer == nil else { return }
        PersistentStoreSnapshotService.requestRestore(snapshot, defaults: defaults)
        retry()
    }

    func enqueueExternalURL(_ url: URL) {
        defaults.set(url.absoluteString, forKey: URLDraftPendingRoute.defaultsKey)
    }

    private func bootstrap() {
        if modelContainer == nil {
            do {
                modelContainer = try makeContainer()
            } catch {
                state = .recoverableFailure(AppLaunchFailure(
                    stage: .openingDatabase,
                    message: error.localizedDescription,
                    snapshots: PersistentStoreSnapshotService.snapshots()
                ))
                return
            }
        }

        guard let modelContainer else { return }
        do {
            state = try initializeContainer(modelContainer)
        } catch {
            state = .recoverableFailure(AppLaunchFailure(
                stage: .initializingData,
                message: error.localizedDescription,
                snapshots: PersistentStoreSnapshotService.snapshots()
            ))
        }
    }

    private static func initialize(
        container: ModelContainer,
        isUITesting: Bool,
        defaults: UserDefaults
    ) throws -> AppLaunchState {
        let context = container.mainContext
        try LegacyTagRemovalService.removeAll(context: context)
        try InitialDataService.seedIfNeeded(context: context)
        try PreviewDataService.seedIfRequested(context: context)

        if isUITesting {
            let books = try context.fetch(FetchDescriptor<LedgerBook>(
                sortBy: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)]
            ))
            defaults.set(
                books.first(where: { !$0.isArchived })?.id.uuidString ?? "",
                forKey: "selectedBookID"
            )
        }

        _ = AutomationDueService(context: context).generateAllDue()

        let hasAccounts = try context.fetchCount(FetchDescriptor<Account>()) > 0
        let hasTransactions = try context.fetchCount(FetchDescriptor<LedgerTransaction>()) > 0
        let completedOnboarding = defaults.bool(forKey: onboardingCompletedKey)
        return completedOnboarding || hasAccounts || hasTransactions ? .ready : .needsOnboarding
    }
}
