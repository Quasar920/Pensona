import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppExperienceSettingsView: View {
    @AppStorage("quickLaunchEntry") private var quickLaunchEntry = false
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                Toggle("启动后直接记一笔", isOn: $quickLaunchEntry)
            } header: {
                Text("秒开记账")
            } footer: {
                Text("App 启动并完成解锁后直接打开记账页。URL Scheme、识别结果等外部草稿仍需单独确认。")
            }
            Section("外观") {
                Picker("显示模式", selection: $appearanceMode) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("启动与外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SecuritySettingsView: View {
    @AppStorage("appLockOnBackground") private var lockOnBackground = true
    @AppStorage("appLockBiometricsEnabled") private var biometricsEnabled = true
    @State private var isConfigured = AppLockCredentialStore().hasCredential()
    @State private var mode: PasswordEditorMode?
    @State private var errorMessage: String?
    private let biometric = BiometricAuthenticator().availability()

    var body: some View {
        Form {
            Section {
                LabeledContent("密码锁", value: isConfigured ? "已开启" : "未开启")
                Button(isConfigured ? "修改密码" : "设置密码") {
                    mode = isConfigured ? .change : .create
                }
                if isConfigured {
                    Button("关闭密码锁", role: .destructive) { mode = .remove }
                }
            } footer: {
                Text("密码经过加盐多轮摘要后只保存在本机系统钥匙串；备份、同步和 URL 中都不包含密码或摘要。")
            }

            Section("锁定行为") {
                Toggle("进入后台后锁定", isOn: $lockOnBackground)
                    .disabled(!isConfigured)
                Toggle("使用 \(biometric.name) 解锁", isOn: $biometricsEnabled)
                    .disabled(!isConfigured || !biometric.available)
                if !biometric.available {
                    Text("当前设备未配置可用的 Face ID、Touch ID 或 Optic ID。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Label("无论是否启用密码锁，App 进入非活动或后台状态时都会显示隐私遮罩，避免系统任务切换截图泄露金额。", systemImage: "eye.slash.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("密码与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $mode) { mode in
            PasswordEditorView(mode: mode) {
                isConfigured = AppLockCredentialStore().hasCredential()
                NotificationCenter.default.post(name: .appLockConfigurationChanged, object: nil)
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }
}

private enum PasswordEditorMode: String, Identifiable {
    case create, change, remove
    var id: String { rawValue }
    var title: String {
        switch self {
        case .create: "设置密码"
        case .change: "修改密码"
        case .remove: "关闭密码锁"
        }
    }
}

private struct PasswordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: PasswordEditorMode
    let completion: () -> Void
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if mode != .create {
                    SecureField("当前密码", text: $currentPassword)
                        .textContentType(.password)
                }
                if mode != .remove {
                    SecureField("新密码（至少 6 位）", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("再次输入新密码", text: $confirmation)
                        .textContentType(.newPassword)
                }
                if mode == .remove {
                    Text("关闭后仍保留后台隐私遮罩，但返回 App 时不再要求解锁。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .remove ? "关闭" : "保存", action: save)
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
            let store = AppLockCredentialStore()
            if mode == .remove {
                try store.remove(currentPassword: currentPassword)
            } else {
                guard newPassword == confirmation else {
                    errorMessage = "两次输入的新密码不一致"
                    return
                }
                try store.setPassword(newPassword, currentPassword: mode == .change ? currentPassword : nil)
            }
            completion()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AppLockGateView: View {
    @ObservedObject var manager: AppLockManager
    let allowsUnlock: Bool
    @State private var password = ""
    @State private var requestedBiometrics = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52)).foregroundStyle(Color.accentColor)
                Text("多币种账本已锁定").font(.title2.bold())
                if allowsUnlock {
                    SecureField("输入密码", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(unlock)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    Button("解锁", action: unlock)
                        .buttonStyle(.borderedProminent)
                        .disabled(password.isEmpty)
                    if manager.canUseBiometrics {
                        Button {
                            Task { await manager.unlockWithBiometrics() }
                        } label: {
                            Label("使用 \(manager.biometricName)", systemImage: "faceid")
                        }
                    }
                    if let message = manager.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                } else {
                    Text("账本内容已隐藏").foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .task {
            guard allowsUnlock, manager.canUseBiometrics, !requestedBiometrics else { return }
            requestedBiometrics = true
            await manager.unlockWithBiometrics()
        }
    }

    private func unlock() {
        manager.unlock(password: password)
        if !manager.isLocked { password = "" }
    }
}
