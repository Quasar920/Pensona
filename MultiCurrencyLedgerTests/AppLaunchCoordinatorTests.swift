import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class AppLaunchCoordinatorTests: XCTestCase {
    private enum TestError: LocalizedError {
        case failed

        var errorDescription: String? { "test failure" }
    }

    func testCapabilitiesKeepReleaseDependentFeaturesDisabled() {
        XCTAssertEqual(
            AppCapabilities.current,
            AppCapabilities(cloudSync: false, cloudSharing: false, productionWidget: false)
        )
    }

    func testStartTransitionsFromInitializingToReadyOnlyOnce() throws {
        let container = try makeContainer()
        var factoryCalls = 0
        var initializerCalls = 0
        let coordinator = AppLaunchCoordinator(
            defaults: makeDefaults(),
            makeContainer: {
                factoryCalls += 1
                return container
            },
            initializeContainer: { _ in
                initializerCalls += 1
                return .ready
            }
        )

        XCTAssertEqual(coordinator.state, .initializing)
        coordinator.startIfNeeded()
        coordinator.startIfNeeded()

        XCTAssertEqual(coordinator.state, .ready)
        XCTAssertTrue(coordinator.modelContainer === container)
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(initializerCalls, 1)
    }

    func testInitializerCanRouteANewInstallToOnboarding() throws {
        let coordinator = AppLaunchCoordinator(
            defaults: makeDefaults(),
            makeContainer: makeContainer,
            initializeContainer: { _ in .needsOnboarding }
        )

        coordinator.startIfNeeded()

        XCTAssertEqual(coordinator.state, .needsOnboarding)
    }

    func testInitializationFailureKeepsContainerAndRetryCanRecover() throws {
        let container = try makeContainer()
        var shouldFail = true
        var factoryCalls = 0
        let coordinator = AppLaunchCoordinator(
            defaults: makeDefaults(),
            makeContainer: {
                factoryCalls += 1
                return container
            },
            initializeContainer: { _ in
                if shouldFail { throw TestError.failed }
                return .ready
            }
        )

        coordinator.startIfNeeded()
        guard case let .recoverableFailure(failure) = coordinator.state else {
            return XCTFail("Expected a recoverable initialization failure")
        }
        XCTAssertEqual(failure.stage, .initializingData)
        XCTAssertEqual(failure.message, "test failure")
        XCTAssertTrue(coordinator.modelContainer === container)

        shouldFail = false
        coordinator.retry()

        XCTAssertEqual(coordinator.state, .ready)
        XCTAssertEqual(factoryCalls, 1)
    }

    func testDatabaseOpenFailureCanRetryWithoutTerminatingTheApp() throws {
        let container = try makeContainer()
        var shouldFail = true
        var factoryCalls = 0
        let coordinator = AppLaunchCoordinator(
            defaults: makeDefaults(),
            makeContainer: {
                factoryCalls += 1
                if shouldFail { throw TestError.failed }
                return container
            },
            initializeContainer: { _ in .ready }
        )

        coordinator.startIfNeeded()
        guard case let .recoverableFailure(failure) = coordinator.state else {
            return XCTFail("Expected a recoverable database failure")
        }
        XCTAssertEqual(failure.stage, .openingDatabase)
        XCTAssertNil(coordinator.modelContainer)

        shouldFail = false
        coordinator.retry()

        XCTAssertEqual(coordinator.state, .ready)
        XCTAssertEqual(factoryCalls, 2)
    }

    func testExternalURLIsQueuedUntilTheReadyRootCanConsumeIt() {
        let defaults = makeDefaults()
        let coordinator = AppLaunchCoordinator(defaults: defaults)
        let url = URL(string: "multicurrencyledger://transaction-draft?type=expense&amount=18")!

        coordinator.enqueueExternalURL(url)

        XCTAssertEqual(
            defaults.string(forKey: URLDraftPendingRoute.defaultsKey),
            url.absoluteString
        )
        XCTAssertEqual(coordinator.state, .initializing)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: LedgerBook.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AppLaunchCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
