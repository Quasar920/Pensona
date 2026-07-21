import SwiftUI
import SwiftData
import Observation

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppPreferences.self) private var preferences
    @StateObject private var appLock = AppLockManager()
    @State private var selection: LedgerTab = .ledger
    @State private var presentation = RootPresentationState()
    @State private var entryVisibilityByTab: [RootEntryTab: RootEntryVisibility] = [:]
    @State private var isLedgerDetailPresented = false
    @State private var isAssetsDetailPresented = false
    @State private var appliedPreviewScreen = false
    @State private var showingPreviewSettings = false
    @State private var appliedQuickLaunch = false
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @AppStorage("quickLaunchEntry") private var quickLaunchEntry = false
    @AppStorage(RecognitionPendingRoute.recordIDDefaultsKey) private var pendingRecognitionRecordID = ""
    @AppStorage(URLDraftPendingRoute.defaultsKey) private var pendingExternalURL = ""
    @Query(sort: \LedgerBook.createdAt) private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \RecognitionImportRecord.createdAt, order: .reverse)
    private var recognitionRecords: [RecognitionImportRecord]
    @State private var pendingRecognitionRecord: RecognitionImportRecord?
    @State private var externalRouteError: String?
    @State private var entrySavedToastID: UUID?

    var body: some View {
        ZStack {
            persistentTab(.ledger) {
                HomeView(
                    addTransaction: presentation.presentNewEntry,
                    isDetailPresented: $isLedgerDetailPresented
                )
                    .rootEntryVisibility(.visible, for: .ledger)
            }
            persistentTab(.assets) {
                AccountListView(isDetailPresented: $isAssetsDetailPresented)
                    .rootEntryVisibility(.visible, for: .assets)
            }
            persistentTab(.savings) {
                SavingsGoalListView()
                    .rootEntryVisibility(.visible, for: .savings)
            }
            persistentTab(.statistics) {
                ReportsView()
                    .rootEntryVisibility(.visible, for: .statistics)
            }
        }
        .onPreferenceChange(RootEntryVisibilityPreferenceKey.self) { visibility in
            entryVisibilityByTab = visibility
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isRootEntryVisible {
                LedgerBottomBar(selection: $selection, addEntry: presentation.presentNewEntry)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay {
            EntryExpansionContainer(presentation: presentation, onEntrySaved: showEntrySavedToast)
                .zIndex(900)
        }
        .overlay(alignment: .bottom) {
            if entrySavedToastID != nil {
                Label("已记账", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .ledgerSurface(.centeredActionPanel, cornerRadius: 22)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(850)
            }
        }
        .sheet(item: $pendingRecognitionRecord, onDismiss: {
            pendingRecognitionRecordID = ""
        }) { record in
            if let book = books.first(where: { $0.id == record.bookID }) {
                RecognitionConfirmationView(record: record, book: book)
            } else {
                ContentUnavailableView("找不到对应账本", systemImage: "book.closed")
            }
        }
        .sheet(isPresented: $showingPreviewSettings) {
            SettingsView()
        }
        .onAppear {
            applyPreviewScreenIfNeeded()
            presentPendingRecognitionIfNeeded()
            presentPendingExternalURLIfNeeded()
            if appLock.isLocked {
                PrivacyShieldController.show(manager: appLock, allowsUnlock: true)
            } else {
                presentQuickLaunchIfNeeded()
            }
        }
        .onOpenURL(perform: handleExternalURL)
        .onChange(of: books.count) { _, _ in
            presentPendingExternalURLIfNeeded()
            presentQuickLaunchIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .onChange(of: appLock.isLocked) { _, locked in
            if locked, scenePhase == .active {
                PrivacyShieldController.show(manager: appLock, allowsUnlock: true)
            } else if !locked, scenePhase == .active {
                PrivacyShieldController.hide()
                presentQuickLaunchIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLockConfigurationChanged)) { _ in
            appLock.refreshConfiguration()
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .environment(\.locale, preferences.locale)
        .id(preferences.language.rawValue)
        .overlay {
            if appLock.isLocked {
                AppLockGateView(manager: appLock, allowsUnlock: true)
                    .ignoresSafeArea()
                    .zIndex(1_000)
            }
        }
        .alert("无法打开记账链接", isPresented: Binding(
            get: { externalRouteError != nil },
            set: { if !$0 { externalRouteError = nil } }
        )) { Button("好") {} } message: { Text(externalRouteError ?? AppLocalization.string("未知错误")) }
    }

    private func persistentTab<Content: View>(
        _ tab: LedgerTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
            .zIndex(selection == tab ? 1 : 0)
    }

    private var isRootEntryVisible: Bool {
        !appLock.isLocked
            && !presentation.isPresentingEntry
            && !selectedTabHasPresentedDetail
            && entryVisibilityByTab[selection.rootEntryTab] != .hidden
    }

    private var selectedTabHasPresentedDetail: Bool {
        switch selection {
        case .ledger: isLedgerDetailPresented
        case .assets: isAssetsDetailPresented
        case .savings, .statistics: false
        }
    }

    private func applyPreviewScreenIfNeeded() {
        #if DEBUG
        guard !appliedPreviewScreen else { return }
        appliedPreviewScreen = true
        switch ProcessInfo.processInfo.environment["APP_PREVIEW_LANGUAGE"] {
        case "en": preferences.language = .english
        case "ja": preferences.language = .japanese
        case "zh-Hant": preferences.language = .traditionalChinese
        case "zh-Hans": preferences.language = .simplifiedChinese
        default: break
        }
        switch ProcessInfo.processInfo.environment["APP_PREVIEW_SCREEN"] {
        case "assets":
            selection = .assets
        case "plans":
            selection = .savings
        case "reports":
            selection = .statistics
        case "entry":
            DispatchQueue.main.async { presentation.presentNewEntry() }
        case "settings":
            DispatchQueue.main.async { showingPreviewSettings = true }
        default:
            break
        }
        #endif
    }

    private func presentPendingRecognitionIfNeeded() {
        guard let id = UUID(uuidString: pendingRecognitionRecordID) else { return }
        pendingRecognitionRecord = recognitionRecords.first { $0.id == id && $0.status == .pendingConfirmation }
    }

    private func presentPendingExternalURLIfNeeded() {
        guard !pendingExternalURL.isEmpty,
              let url = URL(string: pendingExternalURL),
              !books.isEmpty else { return }
        pendingExternalURL = ""
        handleExternalURL(url)
    }

    private func handleExternalURL(_ url: URL) {
        do {
            let request = try URLDraftParser().parse(url)
            let wallets = accounts.filter { !$0.isArchived }.flatMap(\.enabledWallets)
            let preferredBookID = UUID(uuidString: selectedBookID)
            let draft = try URLDraftResolver().resolve(
                request,
                books: books,
                wallets: wallets,
                categories: categories,
                preferredBookID: preferredBookID
            )
            presentation.presentExternalEntry(draft)
        } catch {
            externalRouteError = error.localizedDescription
        }
    }

    private func presentQuickLaunchIfNeeded() {
        guard quickLaunchEntry, !appliedQuickLaunch, !appLock.isLocked,
              !books.isEmpty, pendingRecognitionRecord == nil, !presentation.isPresentingEntry,
              pendingRecognitionRecordID.isEmpty, pendingExternalURL.isEmpty else { return }
        appliedQuickLaunch = true
        DispatchQueue.main.async { presentation.presentNewEntry() }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if appLock.isLocked {
                PrivacyShieldController.show(manager: appLock, allowsUnlock: true)
            } else {
                PrivacyShieldController.hide()
                presentQuickLaunchIfNeeded()
            }
        case .inactive, .background:
            appLock.lockForPrivacyIfNeeded()
            PrivacyShieldController.show(manager: appLock, allowsUnlock: false)
        @unknown default:
            PrivacyShieldController.show(manager: appLock, allowsUnlock: false)
        }
    }

    private func showEntrySavedToast() {
        let id = UUID()
        withAnimation(LedgerMotion.responsive) { entrySavedToastID = id }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard entrySavedToastID == id else { return }
            withAnimation(LedgerMotion.reduced) { entrySavedToastID = nil }
        }
    }
}

struct RootEntryPresentation: Identifiable {
    enum Mode {
        case new
        case external(TransactionDraft)
    }

    let id = UUID()
    let mode: Mode
}

@MainActor
@Observable
final class RootPresentationState {
    var entry: RootEntryPresentation?

    var isPresentingEntry: Bool { entry != nil }

    func presentNewEntry() {
        guard entry == nil else { return }
        entry = RootEntryPresentation(mode: .new)
    }

    func presentExternalEntry(_ draft: TransactionDraft) {
        guard entry == nil else { return }
        entry = RootEntryPresentation(mode: .external(draft))
    }

    func finishDismissal() {
        entry = nil
    }
}

private struct RootEntryButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            entryLabel
        }
        .buttonStyle(RootEntryButtonStyle())
        .accessibilityLabel("记一笔")
        .accessibilityHint("新建一笔交易")
        .accessibilityIdentifier("root-entry-button")
    }

    @ViewBuilder
    private var entryLabel: some View {
        let icon = Image(systemName: "plus")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: RootEntryLayout.diameter, height: RootEntryLayout.diameter)
            .contentShape(Circle())

        if reduceTransparency {
            icon.background {
                Circle().fill(HomePalette.accent)
            }
        } else {
            icon.glassEffect(
                .regular.tint(HomePalette.accent).interactive(),
                in: Circle()
            )
        }
    }
}

private struct RootEntryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(configuration.isPressed ? (reduceMotion ? 0.78 : 0.90) : 1)
            .animation(
                pressAnimation(isPressed: configuration.isPressed),
                value: configuration.isPressed
            )
    }

    private func pressAnimation(isPressed: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: isPressed ? 0.12 : 0.10)
            : .timingCurve(0.23, 1, 0.32, 1, duration: isPressed ? 0.12 : 0.10)
    }
}

enum RootEntryLayout {
    static let diameter: CGFloat = 56
    static let radius = diameter / 2
    static let trailingSpacing: CGFloat = 20
    static let tabBarSpacing: CGFloat = 18
    static let tabBarContentHeight: CGFloat = 49
    static let scrollContentClearance = diameter + tabBarSpacing + 12
}

enum RootEntryTab: Hashable {
    case ledger
    case assets
    case savings
    case statistics
}

enum RootEntryVisibility: Equatable {
    case visible
    case hidden
}

struct RootEntryVisibilityPreferenceKey: PreferenceKey {
    static let defaultValue: [RootEntryTab: RootEntryVisibility] = [:]

    static func reduce(
        value: inout [RootEntryTab: RootEntryVisibility],
        nextValue: () -> [RootEntryTab: RootEntryVisibility]
    ) {
        for (tab, visibility) in nextValue() {
            if value[tab] == .hidden || visibility == .hidden {
                value[tab] = .hidden
            } else {
                value[tab] = .visible
            }
        }
    }
}

extension View {
    func rootEntryVisibility(_ visibility: RootEntryVisibility, for tab: RootEntryTab) -> some View {
        preference(
            key: RootEntryVisibilityPreferenceKey.self,
            value: [tab: visibility]
        )
    }
}

enum LedgerTab: String, CaseIterable, Identifiable {
    case ledger, assets, savings, statistics

    var id: Self { self }

    var title: String {
        switch self {
        case .ledger: AppLocalization.string( "tab.ledger")
        case .assets: AppLocalization.string( "tab.assets")
        case .savings: AppLocalization.string( "tab.plans")
        case .statistics: AppLocalization.string( "tab.reports")
        }
    }

    var symbolName: String {
        switch self {
        case .ledger: "list.bullet.rectangle"
        case .assets: "creditcard"
        case .savings: "target"
        case .statistics: "chart.bar.xaxis"
        }
    }

    var rootEntryTab: RootEntryTab {
        switch self {
        case .ledger: .ledger
        case .assets: .assets
        case .savings: .savings
        case .statistics: .statistics
        }
    }
}
