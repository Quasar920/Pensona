import SwiftUI

struct TransactionFilterView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TransactionQueryState
    @State private var minimumText: String
    @State private var maximumText: String

    let defaultBookID: UUID?
    let books: [LedgerBook]
    let accounts: [Account]
    let categories: [LedgerCategory]
    let apply: (TransactionQueryState) -> Void

    init(
        query: TransactionQueryState,
        defaultBookID: UUID?,
        books: [LedgerBook],
        accounts: [Account],
        categories: [LedgerCategory],
        apply: @escaping (TransactionQueryState) -> Void
    ) {
        _draft = State(initialValue: query)
        _minimumText = State(initialValue: Self.decimalText(query.minimumAmount))
        _maximumText = State(initialValue: Self.decimalText(query.maximumAmount))
        self.defaultBookID = defaultBookID
        self.books = books
        self.accounts = accounts
        self.categories = categories
        self.apply = apply
    }

    private var availableAccounts: [Account] {
        accounts.filter { account in
            !account.isHidden && (draft.bookID == nil || account.book?.id == draft.bookID)
        }
    }

    private var availableCategories: [LedgerCategory] {
        switch draft.kind {
        case .income:
            categories.filter { $0.type == .income }
        case .expense:
            categories.filter { $0.type == .expense }
        case .transfer, .exchange, .adjustment:
            []
        case nil:
            categories
        }
    }

    private var parsedMinimum: Decimal? {
        parseOptionalAmount(minimumText)
    }

    private var parsedMaximum: Decimal? {
        parseOptionalAmount(maximumText)
    }

    private var amountInputsAreValid: Bool {
        let minimumIsValid = minimumText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || parsedMinimum.map { $0 >= 0 } == true
        let maximumIsValid = maximumText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || parsedMaximum.map { $0 >= 0 } == true
        guard minimumIsValid, maximumIsValid else { return false }
        guard let parsedMinimum, let parsedMaximum else { return true }
        return parsedMinimum <= parsedMaximum
    }

    private var canApply: Bool {
        draft.hasValidDateRange && amountInputsAreValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("范围") {
                    Picker("账本", selection: $draft.bookID) {
                        Text("全部账本").tag(nil as UUID?)
                        ForEach(books) { book in
                            Text(book.name).tag(book.id as UUID?)
                        }
                    }

                    Picker("时间", selection: $draft.dateFilter) {
                        ForEach(TransactionDateFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }

                    if draft.dateFilter == .custom {
                        DatePicker("开始日期", selection: customStartBinding, displayedComponents: .date)
                        DatePicker("结束日期", selection: customEndBinding, displayedComponents: .date)
                        if !draft.hasValidDateRange {
                            Label("结束日期不能早于开始日期", systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("金额") {
                    TextField("最低金额（不限）", text: $minimumText)
                        .keyboardType(.decimalPad)
                    TextField("最高金额（不限）", text: $maximumText)
                        .keyboardType(.decimalPad)
                    if !amountInputsAreValid {
                        Label("请输入有效金额，且最低金额不能高于最高金额", systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("交易属性") {
                    Picker("账户", selection: $draft.accountID) {
                        Text("全部账户").tag(nil as UUID?)
                        ForEach(availableAccounts) { account in
                            Text(account.name).tag(account.id as UUID?)
                        }
                    }

                    Picker("币种", selection: $draft.currencyCode) {
                        Text("全部币种").tag(nil as String?)
                        ForEach(SupportedCurrency.allCases) { currency in
                            Text("\(currency.rawValue) · \(currency.localizedName)")
                                .tag(currency.rawValue as String?)
                        }
                    }

                    Picker("类型", selection: $draft.kind) {
                        Text("全部类型").tag(nil as TransactionKind?)
                        ForEach(TransactionKind.allCases) { kind in
                            Text(kind.title).tag(kind as TransactionKind?)
                        }
                    }

                    Picker("分类", selection: $draft.categoryID) {
                        Text("全部分类").tag(nil as UUID?)
                        ForEach(availableCategories) { category in
                            Text(category.name).tag(category.id as UUID?)
                        }
                    }
                    .disabled(availableCategories.isEmpty)
                }

                Section("排序") {
                    Picker("顺序", selection: $draft.sortOrder) {
                        ForEach(TransactionSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                }

                Section {
                    Button("清除全部筛选", role: .destructive, action: clearFilters)
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用", action: applyFilters)
                        .disabled(!canApply)
                }
            }
            .onChange(of: draft.bookID) { _, _ in
                if !availableAccounts.contains(where: { $0.id == draft.accountID }) {
                    draft.accountID = nil
                }
            }
            .onChange(of: draft.kind) { _, _ in
                if !availableCategories.contains(where: { $0.id == draft.categoryID }) {
                    draft.categoryID = nil
                }
            }
            .onChange(of: draft.dateFilter) { _, newValue in
                guard newValue == .custom else { return }
                let today = Calendar.current.startOfDay(for: .now)
                draft.customStartDate = draft.customStartDate ?? today
                draft.customEndDate = draft.customEndDate ?? today
            }
        }
    }

    private var customStartBinding: Binding<Date> {
        Binding(
            get: { draft.customStartDate ?? Calendar.current.startOfDay(for: .now) },
            set: { draft.customStartDate = $0 }
        )
    }

    private var customEndBinding: Binding<Date> {
        Binding(
            get: { draft.customEndDate ?? Calendar.current.startOfDay(for: .now) },
            set: { draft.customEndDate = $0 }
        )
    }

    private func clearFilters() {
        draft.clearFilters(keepingBookID: defaultBookID)
        minimumText = ""
        maximumText = ""
    }

    private func applyFilters() {
        guard canApply else { return }
        draft.minimumAmount = parsedMinimum
        draft.maximumAmount = parsedMaximum
        apply(draft)
        dismiss()
    }

    private func parseOptionalAmount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : DecimalParser.parse(trimmed)
    }

    private static func decimalText(_ value: Decimal?) -> String {
        value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }
}
