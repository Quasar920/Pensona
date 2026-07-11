import SwiftData
import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var group: AssetGroup
    @State private var note = ""
    @State private var errorMessage: String?

    let book: LedgerBook?

    init(book: LedgerBook? = nil, initialGroup: AssetGroup = .cash) {
        self.book = book
        _group = State(initialValue: initialGroup)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $name)
                    Picker("账户类型", selection: $group) {
                        ForEach(AssetGroup.allCases) { item in
                            Label(item.title, systemImage: item.symbolName).tag(item)
                        }
                    }
                    TextField("备注（可选）", text: $note, axis: .vertical)
                }

                Section {
                    Text("保存后可进入账户详情添加币种和初始余额。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新建账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func save() {
        do {
            _ = try AccountService(context: context).createAccount(
                name: name,
                type: group.canonicalAccountType,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                book: book
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
