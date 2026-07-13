import AppIntents

struct LedgerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetRecognitionContextIntent(),
            phrases: ["用\(.applicationName)获取记账候选"],
            shortTitle: "获取记账候选",
            systemImageName: "list.bullet.rectangle"
        )
        AppShortcut(
            intent: RecognizeScreenshotIntent(),
            phrases: ["用\(.applicationName)识别并记账"],
            shortTitle: "识别并记账",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: OpenTransactionDraftIntent(),
            phrases: ["用\(.applicationName)打开待确认记账"],
            shortTitle: "待确认记账",
            systemImageName: "square.and.pencil"
        )
    }
}
