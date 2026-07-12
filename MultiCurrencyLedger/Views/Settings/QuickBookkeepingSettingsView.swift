import SwiftUI
import UIKit

struct QuickBookkeepingSettingsView: View {
    @AppStorage("recognitionAllowIncomeAutoEntry") private var allowIncomeAutoEntry = false

    var body: some View {
        Form {
            Section {
                Text("付款页触发快捷指令后，由快捷指令截屏、OCR 并请求你配置的识别 API；App 只验证结果并写入账本。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("工作方式")
            }

            Section {
                Toggle("允许高置信度收入自动入账", isOn: $allowIncomeAutoEntry)
            } header: {
                Text("自动入账")
            } footer: {
                Text("支出仍需通过本地金额、账户、分类和重复检测。转账、换汇、退款、手续费交易都必须确认。")
            }

            Section {
                Button("打开“快捷指令”") { openShortcuts() }
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 新建快捷指令，添加“截屏”。")
                    Text("2. 添加“从图像提取文本”，输入为截屏。")
                    Text("3. 添加“多币种账本”的“获取记账识别候选”。")
                    Text("4. 用“获取 URL 内容”把 OCR 文本和候选 JSON 发给你的识别 API。")
                    Text("5. 添加“多币种账本”的“识别并记账”，传入 OCR 文本与 API 返回的 JSON。")
                    Text("6. 成功时让快捷指令震动；需要确认时 App 会打开确认页。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("创建快捷指令")
            } footer: {
                Text("API 地址、Token 和提示词由快捷指令管理，不会保存到记账 App。iOS 要求由你确认创建或修改快捷指令。")
            }
        }
        .navigationTitle("快捷记账")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        UIApplication.shared.open(url)
    }
}
