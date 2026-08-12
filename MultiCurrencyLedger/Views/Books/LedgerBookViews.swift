import SwiftData
import SwiftUI

struct LedgerBookSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]

    @Binding var selectedBookID: String
    @State private var showingNewBook = false
    @State private var showingManagement = false

    private var activeBooks: [LedgerBook] {
        books.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        ForEach(activeBooks) { book in
                            Button {
                                selectedBookID = book.id.uuidString
                                dismiss()
                            } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: "book.closed.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 38, height: 38)
                                        .background(Color.accentColor.opacity(0.11), in: Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(book.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text("\(book.accounts.filter { !$0.isHidden }.count) 个资产账户")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if selectedBookID == book.id.uuidString {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityLabel("当前账本")
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("选择要查看的账本")
                    }
                }
                .listStyle(.insetGrouped)

                VStack(spacing: 10) {
                    Button {
                        showingNewBook = true
                    } label: {
                        Label("新建账本", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showingManagement = true
                    } label: {
                        Label("管理账本", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .background(.bar)
            }
            .navigationTitle("切换账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showingNewBook) {
                AddLedgerBookView { book in
                    selectedBookID = book.id.uuidString
                }
            }
            .sheet(isPresented: $showingManagement) {
                LedgerBookManagementView()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct AddLedgerBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let onCreated: (LedgerBook) -> Void
    @State private var name = ""
    @State private var errorMessage: String?

    init(onCreated: @escaping (LedgerBook) -> Void = { _ in }) {
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：旅行账本", text: $name)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("账本名称")
                } footer: {
                    Text("账本用来分开不同场景的资产与记录。")
                }
            }
            .navigationTitle("新建账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建", action: create)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("无法创建", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? AppLocalization.string("未知错误"))
            }
        }
    }

    private func create() {
        do {
            let book = try LedgerBookService(context: context).createBook(name: name)
            onCreated(book)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LedgerBookManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]

    @State private var showingNewBook = false

    private var activeBooks: [LedgerBook] { books.filter { !$0.isArchived } }
    private var archivedBooks: [LedgerBook] { books.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            List {
                Section("使用中的账本") {
                    ForEach(activeBooks) { book in
                        bookRow(book)
                    }
                }
                if !archivedBooks.isEmpty {
                    Section("已归档") {
                        ForEach(archivedBooks) { book in
                            bookRow(book)
                        }
                    }
                }
            }
            .navigationTitle("管理账本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewBook = true } label: {
                        Label("新建账本", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewBook) {
                AddLedgerBookView { book in
                    selectedBookID = book.id.uuidString
                }
            }
        }
    }

    @ViewBuilder
    private func bookRow(_ book: LedgerBook) -> some View {
                    NavigationLink {
                        EditLedgerBookView(book: book)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.name).font(.body.weight(.semibold))
                                Text("\(book.accounts.count) 个账户")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedBookID == book.id.uuidString {
                                Text("当前")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.10), in: Capsule())
                            }
                        }
                        .padding(.vertical, 3)
                    }
    }
}

private struct EditLedgerBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    let book: LedgerBook

    @State private var name: String
    @State private var errorMessage: String?
    @State private var saved = false
    @State private var action: BookAction?
    @State private var containsData = true

    private enum BookAction: Identifiable {
        case archive
        case delete

        var id: String {
            switch self {
            case .archive: "archive"
            case .delete: "delete"
            }
        }
    }

    init(book: LedgerBook) {
        self.book = book
        _name = State(initialValue: book.name)
    }

    var body: some View {
        Form {
            Section("账本名称") {
                if book.isArchived {
                    Text(book.name)
                } else {
                    TextField("账本名称", text: $name)
                }
            }
            Section {
                LabeledContent("资产账户", value: "\(book.accounts.count) 个")
                LabeledContent("创建时间", value: book.createdAt.formatted(date: .abbreviated, time: .omitted))
                if let archivedAt = book.archivedAt {
                    LabeledContent("归档时间", value: archivedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            lifecycleSection
            if saved {
                Label("已保存", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(LedgerPalette.ink)
            }
        }
        .navigationTitle("编辑账本")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: book.updatedAt) {
            containsData = (try? LedgerBookService(context: context).hasContent(in: book)) ?? true
        }
        .toolbar {
            if !book.isArchived {
                Button("保存", action: save)
                    .fontWeight(.semibold)
            }
        }
        .alert("无法保存", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? AppLocalization.string("未知错误"))
        }
        .confirmationDialog(
            action == .archive ? "归档这个账本？" : "删除这个空白账本？",
            isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } })
        ) {
            if action == .archive {
                Button("归档", role: .destructive, action: archive)
            } else if action == .delete {
                Button("删除", role: .destructive, action: delete)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(action == .archive
                 ? "归档后会从日常账本切换中隐藏，且不能继续记账；你可以随时在“已归档”中恢复。"
                 : "删除后无法恢复。")
        }
    }

    @ViewBuilder
    private var lifecycleSection: some View {
        Section("账本状态") {
            if book.isArchived {
                Text("此账本已归档，不会出现在日常账本切换中。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("恢复账本", action: restore)
                    .foregroundStyle(Color.accentColor)
            } else if containsData {
                Text("账本已有内容，只能归档，不能删除。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("归档账本", role: .destructive) { action = .archive }
            } else {
                Text("这是空白账本，可以直接删除。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("删除空白账本", role: .destructive) { action = .delete }
            }
        }
    }

    private func save() {
        do {
            try LedgerBookService(context: context).rename(book, to: name)
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive() {
        performLifecycleChange { service in
            try service.archive(book)
        }
    }

    private func restore() {
        performLifecycleChange { service in
            try service.restore(book)
        }
    }

    private func delete() {
        performLifecycleChange { service in
            try service.delete(book)
        }
    }

    private func performLifecycleChange(_ change: (LedgerBookService) throws -> Void) {
        do {
            try change(LedgerBookService(context: context))
            if selectedBookID == book.id.uuidString {
                selectedBookID = books.first(where: { !$0.isArchived && $0.id != book.id })?.id.uuidString ?? ""
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
