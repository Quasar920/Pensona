import SwiftData
import SwiftUI

struct TransactionTemplateManagementView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \TransactionTemplate.updatedAt, order: .reverse)
    private var templates: [TransactionTemplate]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @State private var showsArchived = false
    @State private var draftToUse: TransactionDraft?
    @State private var errorMessage: String?

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var scopedTemplates: [TransactionTemplate] {
        guard let bookID = selectedBook?.id else { return [] }
        return templates.filter { $0.bookID == bookID && (showsArchived ? $0.isArchived : !$0.isArchived) }
    }

    private var wallets: [CurrencyWallet] {
        guard selectedBook != nil else { return [] }
        return accounts.filter { !$0.isArchived }.flatMap(\.enabledWallets)
    }

    var body: some View {
        List {
            if !books.isEmpty {
                Picker("管理账本", selection: $selectedBookID) {
                    ForEach(books) { Text($0.name).tag($0.id.uuidString) }
                }
            }
            Section(showsArchived ? AppLocalization.string("已归档模板") : AppLocalization.string("可用模板")) {
                if scopedTemplates.isEmpty {
                    Text("可在任意交易详情中保存模板").foregroundStyle(.secondary)
                }
                ForEach(scopedTemplates) { template in
                    Button { use(template) } label: {
                        HStack {
                            Image(systemName: "square.on.square")
                            VStack(alignment: .leading) {
                                Text(template.name).foregroundStyle(.primary)
                                Text(template.type.title + " · " + NSDecimalNumber(decimal: template.amount).stringValue)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .swipeActions {
                        Button(template.isArchived ? AppLocalization.string("恢复") : AppLocalization.string("归档")) {
                            updateArchived(!template.isArchived, template: template)
                        }
                        .tint(template.isArchived ? .green : .orange)
                        Button("删除", role: .destructive) { delete(template) }
                    }
                }
            }
        }
        .navigationTitle("交易模板")
        .toolbar {
            Button { showsArchived.toggle() } label: {
                Image(systemName: showsArchived ? "archivebox.fill" : "archivebox")
            }
        }
        .sheet(item: $draftToUse) { draft in
            EntryView(seed: draft, dismissAfterSave: true)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
    }

    private func use(_ template: TransactionTemplate) {
        do {
            draftToUse = try TransactionTemplateService(context: context).resolve(
                template,
                wallets: wallets,
                categories: categories.filter { !$0.isArchived }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateArchived(_ archived: Bool, template: TransactionTemplate) {
        do { try TransactionTemplateService(context: context).setArchived(archived, template: template) }
        catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ template: TransactionTemplate) {
        do { try TransactionTemplateService(context: context).delete(template) }
        catch { errorMessage = error.localizedDescription }
    }
}

extension TransactionDraft: Identifiable {
    var id: String {
        [
            type.rawValue,
            sourceWallet?.id.uuidString ?? "",
            destinationWallet?.id.uuidString ?? "",
            NSDecimalNumber(decimal: amount).stringValue,
            date.timeIntervalSinceReferenceDate.description
        ].joined(separator: "|")
    }
}
