import SwiftData
import SwiftUI

@main
struct MultiCurrencyLedgerApp: App {
    @State private var preferences = AppPreferences()
    @State private var launchCoordinator = AppLaunchCoordinator()

    var body: some Scene {
        WindowGroup {
            AppLaunchRootView(coordinator: launchCoordinator)
                .environment(preferences)
                .task { launchCoordinator.startIfNeeded() }
                .onOpenURL(perform: launchCoordinator.enqueueExternalURL)
        }
    }
}

private struct AppLaunchRootView: View {
    let coordinator: AppLaunchCoordinator

    var body: some View {
        ZStack {
            switch coordinator.state {
            case .initializing:
                AppLaunchLoadingView()

            case .needsOnboarding, .ready:
                if let container = coordinator.modelContainer {
                    RootTabView()
                        .modelContainer(container)
                } else {
                    AppLaunchLoadingView()
                }

            case let .recoverableFailure(failure):
                AppLaunchRecoveryView(
                    failure: failure,
                    retry: coordinator.retry,
                    restore: coordinator.retryUsing
                )
            }

            if coordinator.isUITesting, coordinator.state != .initializing {
                let failed: Bool = {
                    if case .recoverableFailure = coordinator.state { return true }
                    return false
                }()
                Text(failed ? "seed failed" : "seed ready")
                    .accessibilityIdentifier(failed ? "app-data-seed-failed" : "app-data-ready")
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct AppLaunchLoadingView: View {
    var body: some View {
        ZStack {
            LedgerPageBackground()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("launch.preparing.title")
                    .font(.headline)
                Text("launch.preparing.message")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AppLaunchRecoveryView: View {
    let failure: AppLaunchFailure
    let retry: () -> Void
    let restore: (MigrationStoreSnapshot) -> Void

    var body: some View {
        ZStack {
            LedgerPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("launch.failure.title")
                        .font(.title2.weight(.semibold))

                    Text(failure.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button("launch.failure.retry", action: retry)
                        .buttonStyle(.borderedProminent)

                    if failure.stage == .openingDatabase, !failure.snapshots.isEmpty {
                        Divider()
                        Text("launch.failure.snapshotHeader")
                            .font(.headline)
                        Text("launch.failure.snapshotMessage")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ForEach(failure.snapshots) { snapshot in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(snapshot.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(snapshot.directoryURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("launch.failure.restore") {
                                        restore(snapshot)
                                    }
                                    .buttonStyle(.bordered)

                                    ShareLink(item: snapshot.directoryURL) {
                                        Label("导出", systemImage: "square.and.arrow.up")
                                    }
                                }
                            }
                            .padding(14)
                            .ledgerSurface(.functional, cornerRadius: 18)
                        }
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24)
            }
        }
    }
}
