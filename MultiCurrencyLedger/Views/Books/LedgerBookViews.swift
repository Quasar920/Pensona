import SwiftData
import SwiftUI

struct LedgerBookSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]

    @Binding var selectedBookID: String
    @State private var showingNewBook = false
    @State private var showingManagement = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        ForEach(books) { book in
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

    var body: some View {
        NavigationStack {
            List {
                ForEach(books) { book in
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
}

private struct EditLedgerBookView: View {
    @Environment(\.modelContext) private var context
    let book: LedgerBook

    @State private var name: String
    @State private var errorMessage: String?
    @State private var saved = false

    init(book: LedgerBook) {
        self.book = book
        _name = State(initialValue: book.name)
    }

    var body: some View {
        Form {
            Section("账本名称") {
                TextField("账本名称", text: $name)
            }
            Section {
                LabeledContent("资产账户", value: "\(book.accounts.count) 个")
                LabeledContent("创建时间", value: book.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            if saved {
                Label("已保存", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .navigationTitle("编辑账本")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("保存", action: save)
                .fontWeight(.semibold)
        }
        .alert("无法保存", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? AppLocalization.string("未知错误"))
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
}
