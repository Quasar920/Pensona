import SwiftUI
import UIKit

@MainActor
enum PrivacyShieldController {
    private static var window: UIWindow?

    static func show(manager: AppLockManager, allowsUnlock: Bool) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached }) else { return }
        let shield = window ?? UIWindow(windowScene: scene)
        shield.windowLevel = .alert + 10
        shield.backgroundColor = .systemBackground
        shield.rootViewController = UIHostingController(
            rootView: AppLockGateView(manager: manager, allowsUnlock: allowsUnlock)
        )
        shield.isHidden = false
        shield.makeKeyAndVisible()
        window = shield
    }

    static func hide() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { !$0.isHidden && $0.windowLevel == .normal })?
            .makeKey()
    }
}
