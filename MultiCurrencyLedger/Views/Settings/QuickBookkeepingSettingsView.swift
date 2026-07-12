import SwiftUI
import UIKit

struct QuickBookkeepingSettingsView: View {
    @AppStorage(RecognitionRuntimeConfiguration.endpointDefaultsKey) private var savedEndpoint = ""
    @AppStorage("recognitionAllowIncomeAutoEntry") private var allowIncomeAutoEntry = false
    @State private var endpoint = ""
    @State private var bearerToken = ""
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    var body: some View {
        Form {
            Section {
                Text("截图仅在本机 OCR；发送给识别服务的是 OCR 文字和最小账户/分类候选，原始截图不会保存。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("数据处理")
            }

            Section {
                TextField("HTTPS 网关地址", text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                SecureField("Bearer Token（可选）", text: $bearerToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存服务配置", action: saveConfiguration)
                if !savedEndpoint.isEmpty {
                    Label("已配置 HTTPS 识别服务", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                }
                if let savedMessage {
                    Text(savedMessage).foregroundStyle(.secondary)
                }
            } header: {
                Text("受控识别服务")
            } footer: {
                Text("令牌仅保存在系统 Keychain，不会写入账本、识别记录或源码。")
            }

            Section {
                Toggle("允许高置信度收入自动入账", isOn: $allowIncomeAutoEntry)
            } header: {
                Text("自动入账")
            } footer: {
                Text("支出仍需通过本地金额、账户、分类、重复检测等全部安全门槛；转账、换汇、退款和手续费交易必须确认。")
            }

            Section {
                Button("打开“快捷指令”") { openShortcuts() }
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 新建快捷指令，添加“截屏”操作。")
                    Text("2. 再添加“多币种账本”的“识别并记账”。")
                    Text("3. 将“截屏”的图像输出传给“截图”参数，然后命名为“快捷记账”。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("安装快捷指令")
            } footer: {
                Text("iOS 要求由你确认创建或修改快捷指令，App 不能静默安装。")
            }

            if !savedEndpoint.isEmpty {
                Section {
                    Button("清除识别服务配置", role: .destructive, action: clearConfiguration)
                }
            }
        }
        .navigationTitle("快捷记账")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { endpoint = savedEndpoint }
        .alert("无法保存", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    private func saveConfiguration() {
        do {
            try RecognitionRuntimeConfiguration.save(endpointString: endpoint, bearerToken: bearerToken)
            savedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            bearerToken = ""
            savedMessage = "服务配置已保存"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearConfiguration() {
        do {
            try RecognitionRuntimeConfiguration.clear()
            endpoint = ""
            bearerToken = ""
            savedEndpoint = ""
            savedMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        UIApplication.shared.open(url)
    }
}
