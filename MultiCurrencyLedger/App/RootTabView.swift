import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selection: LedgerTab = .ledger
    @State private var showingNewTransaction = false
    @State private var appliedPreviewScreen = false
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @AppStorage(RecognitionPendingRoute.recordIDDefaultsKey) private var pendingRecognitionRecordID = ""
    @AppStorage(URLDraftPendingRoute.defaultsKey) private var pendingExternalURL = ""
    @Query(sort: \LedgerBook.createdAt) private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \TransactionTag.name) private var tags: [TransactionTag]
    @Query(sort: \RecognitionImportRecord.createdAt, order: .reverse)
    private var recognitionRecords: [RecognitionImportRecord]
    @State private var pendingRecognitionRecord: RecognitionImportRecord?
    @State private var pendingExternalDraft: TransactionDraft?
    @State private var externalRouteError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selection {
                case .ledger:
                    HomeView(addTransaction: { showingNewTransaction = true })
                case .assets:
                    AccountListView()
                case .savings:
                    SavingsGoalListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 72)
            }

            GlassTabBar(
                selection: $selection,
                addTransaction: { showingNewTransaction = true }
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showingNewTransaction) {
            EntryView()
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
        .sheet(item: $pendingExternalDraft) { draft in
            EntryView(
                seed: draft,
                dismissAfterSave: true,
                resetSeedDate: false,
                presentationTitle: "确认外部记账"
            )
        }
        .onAppear {
            applyPreviewScreenIfNeeded()
            presentPendingRecognitionIfNeeded()
            presentPendingExternalURLIfNeeded()
        }
        .onOpenURL(perform: handleExternalURL)
        .onChange(of: books.count) { _, _ in presentPendingExternalURLIfNeeded() }
        .alert("无法打开记账链接", isPresented: Binding(
            get: { externalRouteError != nil },
            set: { if !$0 { externalRouteError = nil } }
        )) { Button("好") {} } message: { Text(externalRouteError ?? "未知错误") }
    }

    private func applyPreviewScreenIfNeeded() {
        #if DEBUG
        guard !appliedPreviewScreen else { return }
        appliedPreviewScreen = true
        switch ProcessInfo.processInfo.environment["APP_PREVIEW_SCREEN"] {
        case "assets":
            selection = .assets
        case "entry":
            DispatchQueue.main.async { showingNewTransaction = true }
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
            pendingExternalDraft = try URLDraftResolver().resolve(
                request,
                books: books,
                wallets: wallets,
                categories: categories,
                tags: tags,
                preferredBookID: preferredBookID
            )
        } catch {
            externalRouteError = error.localizedDescription
        }
    }
}

private enum LedgerTab: String, CaseIterable, Identifiable {
    case ledger, assets, savings

    var id: Self { self }

    var title: String {
        switch self {
        case .ledger: "账本"
        case .assets: "资产"
        case .savings: "存钱"
        }
    }

    var symbolName: String {
        switch self {
        case .ledger: "book.closed.fill"
        case .assets: "creditcard.fill"
        case .savings: "banknote.fill"
        }
    }
}

private struct GlassTabBar: View {
    @Binding var selection: LedgerTab
    let addTransaction: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LedgerTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .opacity(0.48)
                                .overlay {
                                    Capsule().fill(Color.accentColor.opacity(0.08))
                                }
                                .matchedGeometryEffect(id: "selectedTab", in: tabNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }

            Button(action: addTransaction) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 46)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.74)
                            .overlay {
                                Circle().fill(Color.accentColor.opacity(0.08))
                            }
                            .overlay {
                                Circle().stroke(Color.accentColor.opacity(0.24), lineWidth: 0.8)
                            }
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("记一笔")
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.56)
        }
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 20, y: 9)
    }

    @Namespace private var tabNamespace
}
