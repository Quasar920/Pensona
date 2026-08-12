import SwiftUI

struct FeeTemplateManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FeeRateTemplateStore
    let kind: TransactionKind

    @State private var editingID: UUID?
    @State private var name = ""
    @State private var percentageText = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("手续费模板") {
                    if templates.isEmpty {
                        Text("暂无模板")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(templates) { template in
                        Button {
                            editingID = template.id
                            name = template.name
                            percentageText = NSDecimalNumber(decimal: template.percentage).stringValue
                            validationMessage = nil
                        } label: {
                            HStack {
                                Text(template.name)
                                Spacer()
                                Text("\(NSDecimalNumber(decimal: template.percentage).stringValue)%")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { store.delete(at: $0, kind: kind) }
                }

                Section(editingID == nil ? "新增模板" : "修改模板") {
                    TextField("模板名称", text: $name)
                    HStack {
                        Text("比例")
                        Spacer()
                        TextField("0.38", text: $percentageText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button(editingID == nil ? "添加模板" : "保存修改", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if editingID != nil {
                        Button("取消修改") {
                            resetEditor()
                        }
                    }
                }
            }
            .navigationTitle(kind == .income ? "收入手续费模板" : "手续费模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var templates: [FeeRateTemplate] {
        store.templates(for: kind)
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let percentage = DecimalParser.parse(percentageText),
              percentage > 0 else {
            validationMessage = "请输入有效的名称和手续费比例"
            return
        }
        store.save(FeeRateTemplate(
            id: editingID ?? UUID(),
            name: cleanName,
            percentage: percentage,
            applicableKind: kind
        ))
        resetEditor()
    }

    private func resetEditor() {
        editingID = nil
        name = ""
        percentageText = ""
        validationMessage = nil
    }
}
