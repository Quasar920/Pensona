import SwiftUI
import SwiftData
import Observation

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
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
    @Query(sort: \TransactionTemplate.updatedAt, order: .reverse)
    private var templates: [TransactionTemplate]
    @Query(sort: \RecognitionImportRecord.createdAt, order: .reverse)
    private var recognitionRecords: [RecognitionImportRecord]
    @State private var pendingRecognitionRecord: RecognitionImportRecord?
    @State private var externalRouteError: String?
    @State private var tapLogError: String?
    @State private var entrySavedToastID: UUID?

    var body: some View {
        Group {
            switch selection {
            case .ledger:
                HomeView(
                    addTransaction: presentation.presentNewEntry,
                    editTransaction: presentation.presentEdit,
                    openReports: { selection = .statistics },
                    isDetailPresented: $isLedgerDetailPresented
                )
                .rootEntryVisibility(.visible, for: .ledger)
            case .assets:
                AccountListView(isDetailPresented: $isAssetsDetailPresented)
                .rootEntryVisibility(.visible, for: .assets)
            case .savings:
                SavingsGoalListView()
                .rootEntryVisibility(.visible, for: .savings)
            case .statistics:
                ReportsView()
                .rootEntryVisibility(.visible, for: .statistics)
            }
        }
        .onPreferenceChange(RootEntryVisibilityPreferenceKey.self) { visibility in
            entryVisibilityByTab = visibility
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isRootEntryVisible {
                VStack(alignment: .trailing, spacing: 6) {
                    if selection == .ledger {
                        TapLogMenu(templates: scopedTapLogTemplates, record: recordTapLogTemplate)
                            .padding(.trailing, LedgerLayout.pagePadding)
                    }

                    LedgerBottomBar(selection: $selection, addEntry: presentation.presentNewEntry)
                }
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
            DispatchQueue.main.async { consumePendingEntrancesIfNeeded() }
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
            consumePendingEntrancesIfNeeded()
        }
        .onChange(of: books.count) { _, _ in
            consumePendingEntrancesIfNeeded()
        }
        .onChange(of: pendingRecognitionRecordID) { _, _ in
            consumePendingEntrancesIfNeeded()
        }
        .onChange(of: pendingExternalURL) { _, _ in
            consumePendingEntrancesIfNeeded()
        }
        .onChange(of: presentation.isPresentingEntry) { _, isPresenting in
            if !isPresenting { consumePendingEntrancesIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .onChange(of: appLock.isLocked) { _, locked in
            if !locked, scenePhase == .active {
                consumePendingEntrancesIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLockConfigurationChanged)) { _ in
            appLock.refreshConfiguration()
        }
        .tint(LedgerPalette.accent)
        .preferredColorScheme(.light)
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
        .alert("TapLog 记账失败", isPresented: Binding(
            get: { tapLogError != nil },
            set: { if !$0 { tapLogError = nil } }
        )) { Button("好") {} } message: {
            Text(tapLogError ?? AppLocalization.string("未知错误"))
        }
    }

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID }
            ?? books.first { !$0.isArchived }
    }

    private var scopedTapLogTemplates: [TransactionTemplate] {
        guard let bookID = selectedBook?.id else { return [] }
        return templates.filter { $0.bookID == bookID && !$0.isArchived }
    }

    private var availableWallets: [CurrencyWallet] {
        accounts.filter { !$0.isArchived }.flatMap(\.enabledWallets)
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

    private func consumePendingEntrancesIfNeeded() {
        guard !appLock.isLocked else { return }
        if presentPendingRecognitionIfNeeded() { return }
        if presentPendingExternalURLIfNeeded() { return }
        presentQuickLaunchIfNeeded()
    }

    @discardableResult
    private func presentPendingRecognitionIfNeeded() -> Bool {
        if pendingRecognitionRecord != nil { return true }
        guard !presentation.isPresentingEntry,
              let id = UUID(uuidString: pendingRecognitionRecordID) else { return false }
        guard let record = recognitionRecords.first(where: {
            $0.id == id && $0.status == .pendingConfirmation
        }) else {
            pendingRecognitionRecordID = ""
            return false
        }
        pendingRecognitionRecord = record
        return true
    }

    @discardableResult
    private func presentPendingExternalURLIfNeeded() -> Bool {
        guard pendingRecognitionRecord == nil,
              pendingRecognitionRecordID.isEmpty,
              !presentation.isPresentingEntry,
              !pendingExternalURL.isEmpty,
              !books.isEmpty else { return false }
        guard let url = URL(string: pendingExternalURL) else {
            pendingExternalURL = ""
            externalRouteError = AppLocalization.string("brand.error.unsupportedURL")
            return true
        }
        pendingExternalURL = ""
        handleExternalURL(url)
        return true
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
            if !appLock.isLocked {
                consumePendingEntrancesIfNeeded()
            }
        case .inactive, .background:
            appLock.lockForPrivacyIfNeeded()
        @unknown default:
            break
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

    private func recordTapLogTemplate(_ template: TransactionTemplate) {
        do {
            let draft = try TransactionTemplateService(context: modelContext).resolve(
                template,
                wallets: availableWallets,
                categories: categories.filter { !$0.isArchived },
                date: .now
            )
            try LedgerService(context: modelContext).create(draft, bookID: template.bookID)
            HapticFeedbackService().notification(.success)
            showEntrySavedToast()
        } catch {
            HapticFeedbackService().notification(.error)
            tapLogError = error.localizedDescription
        }
    }
}

private struct TapLogMenu: View {
    let templates: [TransactionTemplate]
    let record: (TransactionTemplate) -> Void

    var body: some View {
        Menu {
            if templates.isEmpty {
                Text("暂无可用模板")
            } else {
                ForEach(templates) { template in
                    Button {
                        record(template)
                    } label: {
                        Label(template.name, systemImage: template.type.symbolName)
                    }
                }
            }
        } label: {
            Label("TapLog", systemImage: "bolt.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LedgerPalette.ink)
                .padding(.horizontal, 13)
                .frame(minHeight: 36)
                .background(LedgerPalette.surface, in: Capsule())
                .overlay(Capsule().stroke(LedgerPalette.hairline, lineWidth: 1))
                .shadow(color: LedgerPalette.ink.opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .accessibilityLabel("TapLog 快捷记账")
        .accessibilityHint("选择模板后直接记账")
        .accessibilityIdentifier("taplog-button")
    }
}

struct RootEntryPresentation: Identifiable {
    enum Mode {
        case new
        case external(TransactionDraft)
        case edit(LedgerTransaction)
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

    func presentEdit(_ transaction: LedgerTransaction) {
        guard entry == nil else { return }
        entry = RootEntryPresentation(mode: .edit(transaction))
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
        case .ledger: "账"
        case .assets: "业"
        case .savings: "策"
        case .statistics: "衡"
        }
    }

    var symbolName: String {
        switch self {
        case .ledger: "list.bullet"
        case .assets: "rectangle.on.rectangle"
        case .savings: "target"
        case .statistics: "chart.bar"
        }
    }

    var selectedSymbolName: String {
        switch self {
        case .ledger: "list.bullet"
        case .assets: "rectangle.on.rectangle"
        case .savings: "target"
        case .statistics: "chart.bar"
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
