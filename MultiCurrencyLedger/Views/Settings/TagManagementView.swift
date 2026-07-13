import SwiftData
import SwiftUI

struct TagManagementView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \TransactionTag.name) private var tags: [TransactionTag]
    @State private var showingAdd = false
    @State private var editingTag: TransactionTag?
    @State private var showsArchived = false
    @State private var errorMessage: String?

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var scopedTags: [TransactionTag] {
        guard let bookID = selectedBook?.id else { return [] }
        return tags.filter { $0.bookID == bookID && (showsArchived ? $0.isArchived : !$0.isArchived) }
    }

    var body: some View {
        List {
            if !books.isEmpty {
                Picker("管理账本", selection: $selectedBookID) {
                    ForEach(books) { Text($0.name).tag($0.id.uuidString) }
                }
            }
            Section(showsArchived ? "已归档标签" : "可用标签") {
                if scopedTags.isEmpty {
                    Text("暂无标签").foregroundStyle(.secondary)
                }
                ForEach(scopedTags) { tag in
                    Button { editingTag = tag } label: {
                        HStack {
                            Image(systemName: "tag.fill").foregroundStyle(Color.accentColor)
                            Text(tag.name).foregroundStyle(.primary)
                            Spacer()
                            if tag.isArchived { Text("已归档").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .swipeActions {
                        Button(tag.isArchived ? "恢复" : "归档") {
                            setArchived(!tag.isArchived, tag: tag)
                        }
                        .tint(tag.isArchived ? .green : .orange)
                    }
                }
            }
        }
        .navigationTitle("标签管理")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showsArchived.toggle() } label: {
                    Image(systemName: showsArchived ? "archivebox.fill" : "archivebox")
                }
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .disabled(selectedBook == nil)
            }
        }
        .sheet(isPresented: $showingAdd) {
            if let bookID = selectedBook?.id { TagEditorView(bookID: bookID, tag: nil) }
        }
        .sheet(item: $editingTag) { tag in
            TagEditorView(bookID: tag.bookID, tag: tag)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    private func setArchived(_ archived: Bool, tag: TransactionTag) {
        do {
            try TagService(context: context).setArchived(archived, tag: tag)
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct TagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let bookID: UUID
    let tag: TransactionTag?
    @State private var name: String
    @State private var colorHex: String
    @State private var errorMessage: String?
    private let colors = ["#5B8DEF", "#41A66B", "#E08A3E", "#D65757", "#8A63D2", "#64748B"]

    init(bookID: UUID, tag: TransactionTag?) {
        self.bookID = bookID
        self.tag = tag
        _name = State(initialValue: tag?.name ?? "")
        _colorHex = State(initialValue: tag?.colorHex ?? "#5B8DEF")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标签名称", text: $name)
                Picker("颜色", selection: $colorHex) {
                    ForEach(colors, id: \.self) { Text($0).tag($0) }
                }
            }
            .navigationTitle(tag == nil ? "新建标签" : "编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func save() {
        do {
            let service = TagService(context: context)
            if let tag {
                try service.update(tag, name: name, colorHex: colorHex)
            } else {
                try service.create(name: name, colorHex: colorHex, bookID: bookID)
            }
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
