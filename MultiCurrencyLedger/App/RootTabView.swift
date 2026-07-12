import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selection: LedgerTab = .ledger
    @State private var showingNewTransaction = false
    @State private var appliedPreviewScreen = false
    @AppStorage(RecognitionPendingRoute.recordIDDefaultsKey) private var pendingRecognitionRecordID = ""
    @Query(sort: \LedgerBook.createdAt) private var books: [LedgerBook]
    @Query(sort: \RecognitionImportRecord.createdAt, order: .reverse)
    private var recognitionRecords: [RecognitionImportRecord]
    @State private var pendingRecognitionRecord: RecognitionImportRecord?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selection {
                case .ledger:
                    HomeView(addTransaction: { showingNewTransaction = true })
                case .assets:
                    AccountListView()
                case .savings:
                    SavingsView(addTransaction: { showingNewTransaction = true })
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
        .onAppear {
            applyPreviewScreenIfNeeded()
            presentPendingRecognitionIfNeeded()
        }
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

private struct SavingsView: View {
    let addTransaction: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ContentUnavailableView {
                    Label("设定一个存钱目标", systemImage: "target")
                } description: {
                    Text("目标账户和自动转入将在后续版本提供。\n现在可以先记录一笔存入。")
                } actions: {
                    Button("记录一笔", action: addTransaction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("存钱")
        }
    }
}
