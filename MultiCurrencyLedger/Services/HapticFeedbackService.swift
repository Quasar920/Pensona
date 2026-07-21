import UIKit

@MainActor
struct HapticFeedbackService {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    private var isEnabled: Bool {
        defaults.object(forKey: AppPreferences.hapticsKey) as? Bool ?? true
    }
}
