import SwiftData
import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var type: AccountType
    @State private var note = ""
    @State private var cardLastFour = ""
    @State private var errorMessage: String?

    let book: LedgerBook?

    init(book: LedgerBook? = nil, initialGroup: AssetGroup = .cash) {
        self.book = book
        _type = State(initialValue: initialGroup == .cash ? .bankCard : initialGroup.canonicalAccountType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $name)
                    Picker("账户类型", selection: $type) {
                        ForEach(AccountType.allCases) { item in
                            Label(item.title, systemImage: item.symbolName).tag(item)
                        }
                    }
                    TextField("备注（可选）", text: $note, axis: .vertical)
                }

                if type.supportsCardLastFour {
                    Section {
                        TextField("选填", text: $cardLastFour)
                            .keyboardType(.numberPad)
                            .onChange(of: cardLastFour) { _, value in
                                let sanitized = AccountCardIdentityStore.sanitizedInput(value)
                                if sanitized != value { cardLastFour = sanitized }
                            }
                    } header: {
                        Text("银行卡后四位")
                    } footer: {
                        Text("用于快捷指令记账时快速识别账户。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                type: type,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                cardLastFour: type.supportsCardLastFour ? cardLastFour : nil,
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
