import Foundation

/// Central switchboard for product capabilities that require release-time
/// infrastructure or signing. Keep unavailable features out of user-facing
/// navigation without deleting their implementation.
struct AppCapabilities: Equatable, Sendable {
    let cloudSync: Bool
    let cloudSharing: Bool
    let productionWidget: Bool

    static let current = AppCapabilities(
        cloudSync: false,
        cloudSharing: false,
        productionWidget: false
    )
}
