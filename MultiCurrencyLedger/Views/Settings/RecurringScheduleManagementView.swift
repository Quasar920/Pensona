import SwiftData
import SwiftUI

struct RecurringScheduleManagementView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \RecurringSchedule.nextDueDate) private var schedules: [RecurringSchedule]
    @Query private var occurrences: [RecurringOccurrence]
    @State private var showingAdd = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var scopedSchedules: [RecurringSchedule] {
        guard let bookID = selectedBook?.id else { return [] }
        return schedules.filter { $0.bookID == bookID && !$0.isArchived }
    }

    private var wallets: [CurrencyWallet] {
        guard let bookID = selectedBook?.id else { return [] }
        return accounts.filter { !$0.isArchived && $0.book?.id == bookID }.flatMap(\.enabledWallets)
    }

    var body: some View {
        List {
            if scopedSchedules.isEmpty {
                ContentUnavailableView {
                    Label("还没有周期账单", systemImage: "repeat.circle")
                } description: {
                    Text("可按天、周、月或年生成普通交易。App 启动时会自动扫描，重复执行不会重复入账。")
                } actions: {
                    Button("新建周期账单") { showingAdd = true }
                }
            } else {
                ForEach(scopedSchedules) { schedule in
                    scheduleRow(schedule)
                }
            }
            if let resultMessage {
                Section { Label(resultMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .navigationTitle("周期账单")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Label("新建", systemImage: "plus") }
                    .disabled(selectedBook == nil || wallets.isEmpty)
            }
        }
        .sheet(isPresented: $showingAdd) {
            if let book = selectedBook {
                RecurringScheduleEditorView(
                    book: book,
                    wallets: wallets,
                    categories: categories.filter {
                        !$0.isArchived && ($0.bookID == nil || $0.bookID == book.id)
                    }
                )
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    @ViewBuilder
    private func scheduleRow(_ schedule: RecurringSchedule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(schedule.name).font(.headline)
                    Text("每 \(schedule.interval) \(schedule.frequency.title) · 下次 \(schedule.nextDueDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("已生成 \(occurrences.filter { $0.scheduleID == schedule.id }.count) 笔")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if schedule.isPaused { Text("已暂停").font(.caption).foregroundStyle(.orange) }
            }
            HStack {
                Button("补生成到今天") { generate(schedule) }
                    .buttonStyle(.bordered)
                    .disabled(schedule.isPaused)
                Button(schedule.isPaused ? "恢复" : "暂停") { togglePause(schedule) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("归档", role: .destructive) { archive(schedule) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func generate(_ schedule: RecurringSchedule) {
        do {
            let count = try RecurringScheduleService(context: context)
                .generateDue(for: schedule).count
            resultMessage = count == 0 ? "当前没有到期账单" : "已生成 \(count) 笔周期交易"
        } catch { errorMessage = error.localizedDescription }
    }

    private func togglePause(_ schedule: RecurringSchedule) {
        do { try RecurringScheduleService(context: context).setPaused(!schedule.isPaused, schedule: schedule) }
        catch { errorMessage = error.localizedDescription }
    }

    private func archive(_ schedule: RecurringSchedule) {
        do { try RecurringScheduleService(context: context).setArchived(true, schedule: schedule) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct RecurringScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let book: LedgerBook
    let wallets: [CurrencyWallet]
    let categories: [LedgerCategory]
    @State private var name = ""
    @State private var frequency: RecurringFrequency = .monthly
    @State private var interval = 1
    @State private var hasEndDate = false
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var form = TransactionFormState()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("名称", text: $name)
                    HStack {
                        Stepper("每 \(interval) \(frequency.title)", value: $interval, in: 1...99)
                        Picker("周期", selection: $frequency) {
                            ForEach(RecurringFrequency.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    Toggle("设置结束日期", isOn: $hasEndDate)
                    if hasEndDate { DatePicker("结束日期", selection: $endDate) }
                }
                TransactionFormSections(
                    state: $form,
                    wallets: wallets,
                    categories: categories
                )
                Section {
                    Text("首次到期日使用交易日期。月度规则会记住原始日期，例如 31 日会在短月落到月末。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新建周期账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear(perform: initialize)
            .onChange(of: form.kind) { _, _ in initializeForKind() }
            .onChange(of: form.sourceWalletID) { _, _ in ensureMovementSelections() }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func initialize() {
        if form.sourceWalletID == nil { form.sourceWalletID = wallets.first?.id }
        initializeForKind()
    }

    private func initializeForKind() {
        if form.kind == .expense || form.kind == .income {
            let type: CategoryKind = form.kind == .income ? .income : .expense
            if !categories.contains(where: { $0.id == form.categoryID && $0.type == type }) {
                form.categoryID = categories.first { $0.type == type }?.id
            }
        } else {
            form.categoryID = nil
        }
        ensureMovementSelections()
    }

    private func ensureMovementSelections() {
        guard let source = wallets.first(where: { $0.id == form.sourceWalletID }) else { return }
        if form.kind == .transfer || form.kind == .exchange {
            let options = wallets.filter {
                $0.id != source.id && (form.kind == .transfer
                    ? $0.currencyCode == source.currencyCode
                    : $0.currencyCode != source.currencyCode)
            }
            if !options.contains(where: { $0.id == form.destinationWalletID }) {
                form.destinationWalletID = options.first?.id
            }
            form.feeWalletID = form.feeWalletID ?? source.id
        }
    }

    private func save() {
        do {
            let draft = try form.makeDraft(wallets: wallets, categories: categories)
            try RecurringScheduleService(context: context).create(
                name: name,
                draft: draft,
                frequency: frequency,
                interval: interval,
                startDate: form.date,
                endDate: hasEndDate ? endDate : nil
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
