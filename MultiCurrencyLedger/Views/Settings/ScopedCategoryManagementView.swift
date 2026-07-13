import SwiftData
import SwiftUI

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: [SortDescriptor(\LedgerCategory.typeRawValue), SortDescriptor(\LedgerCategory.sortOrder)])
    private var categories: [LedgerCategory]
    @State private var showingAdd = false
    @State private var editingCategory: LedgerCategory?
    @State private var showsArchived = false
    @State private var errorMessage: String?

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    var body: some View {
        List {
            if let book = selectedBook {
                Section {
                    Picker("管理账本", selection: $selectedBookID) {
                        ForEach(books) { Text($0.name).tag($0.id.uuidString) }
                    }
                }
                categorySection(.expense, title: "支出分类", bookID: book.id)
                categorySection(.income, title: "收入分类", bookID: book.id)
            } else {
                ContentUnavailableView("请先创建账本", systemImage: "book.closed")
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsArchived.toggle()
                } label: {
                    Image(systemName: showsArchived ? "archivebox.fill" : "archivebox")
                }
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .disabled(selectedBook == nil)
            }
        }
        .sheet(isPresented: $showingAdd) {
            if let bookID = selectedBook?.id {
                CategoryEditorView(bookID: bookID, category: nil, categories: scopedCategories(bookID: bookID))
            }
        }
        .sheet(item: $editingCategory) { category in
            if let bookID = selectedBook?.id {
                CategoryEditorView(bookID: bookID, category: category, categories: scopedCategories(bookID: bookID))
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func categorySection(_ type: CategoryKind, title: String, bookID: UUID) -> some View {
        let nodes = flattenedNodes(type: type, bookID: bookID)
        return Section(title) {
            if nodes.isEmpty {
                Text(showsArchived ? "没有已归档分类" : "暂无分类")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nodes, id: \.category.id) { node in
                    Button {
                        guard !node.category.isSystem else { return }
                        editingCategory = node.category
                    } label: {
                        HStack(spacing: 10) {
                            Color.clear.frame(width: CGFloat(node.level) * 18)
                            Image(systemName: node.category.symbolName)
                                .foregroundStyle(node.category.isArchived ? .secondary : Color.accentColor)
                            Text(node.category.name)
                                .foregroundStyle(node.category.isArchived ? .secondary : .primary)
                            Spacer()
                            if node.category.isSystem {
                                Text("系统")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if node.category.isArchived {
                                Text("已归档")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if !node.category.isSystem {
                            Button(node.category.isArchived ? "恢复" : "归档") {
                                setArchived(!node.category.isArchived, category: node.category)
                            }
                            .tint(node.category.isArchived ? .green : .orange)
                        }
                    }
                }
            }
        }
    }

    private func scopedCategories(bookID: UUID) -> [LedgerCategory] {
        categories.filter { category in
            (category.bookID == nil || category.bookID == bookID)
                && (showsArchived ? category.isArchived : !category.isArchived)
        }
    }

    private func flattenedNodes(type: CategoryKind, bookID: UUID) -> [CategoryNode] {
        let scoped = scopedCategories(bookID: bookID).filter { $0.type == type }
        func appendChildren(parentID: UUID?, level: Int, to output: inout [CategoryNode]) {
            let children = scoped.filter { $0.parentID == parentID }.sorted {
                $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
            }
            for child in children {
                output.append(CategoryNode(category: child, level: level))
                appendChildren(parentID: child.id, level: level + 1, to: &output)
            }
        }
        var result: [CategoryNode] = []
        appendChildren(parentID: nil, level: 0, to: &result)
        return result
    }

    private func setArchived(_ archived: Bool, category: LedgerCategory) {
        do {
            try CategoryService(context: context).setArchived(archived, category: category)
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct CategoryNode {
    let category: LedgerCategory
    let level: Int
}

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let bookID: UUID
    let category: LedgerCategory?
    let categories: [LedgerCategory]
    @State private var name: String
    @State private var type: CategoryKind
    @State private var symbolName: String
    @State private var parentID: UUID?
    @State private var errorMessage: String?

    private let symbols = ["tag", "star", "heart", "cup.and.saucer", "car", "bag", "house", "briefcase", "gift", "fork.knife", "cart"]

    init(bookID: UUID, category: LedgerCategory?, categories: [LedgerCategory]) {
        self.bookID = bookID
        self.category = category
        self.categories = categories
        _name = State(initialValue: category?.name ?? "")
        _type = State(initialValue: category?.type ?? .expense)
        _symbolName = State(initialValue: category?.symbolName ?? "tag")
        _parentID = State(initialValue: category?.parentID)
    }

    private var parentOptions: [LedgerCategory] {
        categories.filter {
            !$0.isArchived && $0.type == type && $0.id != category?.id && $0.parentID == nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("分类名称", text: $name)
                Picker("类型", selection: $type) {
                    Text("支出").tag(CategoryKind.expense)
                    Text("收入").tag(CategoryKind.income)
                }
                .disabled(category != nil)
                Picker("上级分类", selection: $parentID) {
                    Text("一级分类").tag(nil as UUID?)
                    ForEach(parentOptions) { Text($0.name).tag($0.id as UUID?) }
                }
                Picker("图标", selection: $symbolName) {
                    ForEach(symbols, id: \.self) { Label($0, systemImage: $0).tag($0) }
                }
            }
            .navigationTitle(category == nil ? "新建分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onChange(of: type) { _, _ in parentID = nil }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func save() {
        let parent = categories.first { $0.id == parentID }
        do {
            let service = CategoryService(context: context)
            if let category {
                try service.update(category, name: name, symbolName: symbolName, parent: parent)
            } else {
                try service.create(
                    name: name,
                    type: type,
                    symbolName: symbolName,
                    bookID: bookID,
                    parent: parent
                )
            }
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
