import AppIntents

struct LedgerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecognizeScreenshotIntent(),
            phrases: ["用\(.applicationName)识别并记账"],
            shortTitle: "识别并记账",
            systemImageName: "text.viewfinder"
        )
    }
}
