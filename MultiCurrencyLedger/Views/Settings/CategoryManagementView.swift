import SwiftData
import SwiftUI

struct CategoryManagementView: View {
    @Query(sort: [SortDescriptor(\LedgerCategory.typeRawValue), SortDescriptor(\LedgerCategory.sortOrder)])
    private var categories: [LedgerCategory]
    @State private var showingAdd = false

    var body: some View {
        List {
            categorySection(.expense, title: "支出分类")
            categorySection(.income, title: "收入分类")
        }
        .navigationTitle("分类管理")
        .toolbar { Button { showingAdd = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingAdd) { AddCategoryView() }
    }

    private func categorySection(_ type: CategoryKind, title: String) -> some View {
        Section(title) {
            ForEach(categories.filter { $0.type == type }) { category in
                HStack {
                    Label(category.name, systemImage: category.symbolName)
                    Spacer()
                    if category.isSystem { Text("系统").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

private struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var type: CategoryKind = .expense
    @State private var symbolName = "tag"
    @State private var errorMessage: String?
    private let symbols = ["tag", "star", "heart", "cup.and.saucer", "car", "bag", "house", "briefcase", "gift"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("分类名称", text: $name)
                Picker("类型", selection: $type) {
                    Text("支出").tag(CategoryKind.expense)
                    Text("收入").tag(CategoryKind.income)
                }
                Picker("图标", selection: $symbolName) {
                    ForEach(symbols, id: \.self) { Label($0, systemImage: $0).tag($0) }
                }
            }
            .navigationTitle("新建分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "请输入分类名称"; return }
        do {
            context.insert(LedgerCategory(name: trimmed, type: type, symbolName: symbolName, sortOrder: 100, isSystem: false))
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
