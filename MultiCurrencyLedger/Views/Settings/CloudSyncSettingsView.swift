import SwiftData
import SwiftUI

struct CloudSyncSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(CloudSyncService.enabledKey) private var isEnabled = false
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @Query(sort: \CloudSyncConflictCopy.createdAt, order: .reverse) private var conflicts: [CloudSyncConflictCopy]
    @State private var availability = "尚未检查"
    @State private var isWorking = false
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    @State private var showingDeleteCloudConfirmation = false

    private var unresolved: [CloudSyncConflictCopy] { conflicts.filter { $0.resolvedAt == nil } }
    private var lastSyncAt: Date? { UserDefaults.standard.object(forKey: CloudSyncService.lastSyncAtKey) as? Date }

    var body: some View {
        Form {
            Section {
                Toggle("启用 iCloud 私有同步", isOn: $isEnabled)
                LabeledContent("账户状态", value: availability)
                if let lastSyncAt {
                    LabeledContent("最近同步") {
                        Text(lastSyncAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                Button(isWorking ? "同步中…" : "立即同步", action: startSync)
                    .disabled(!isEnabled || isWorking)
                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("同步")
            } footer: {
                Text("默认关闭。开启后使用你账号的 CloudKit 私有数据库；本机和云端同时修改时不会自动覆盖，而是生成冲突副本。关闭开关只停止同步，不删除云端数据。")
            }

            if !unresolved.isEmpty {
                Section("待处理冲突") {
                    ForEach(unresolved) { conflict in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("来自设备 \(conflict.remoteDeviceID.prefix(8))")
                                .font(.headline)
                            Text(conflict.remoteModifiedAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("保留本机") { keepLocal(conflict) }
                                    .buttonStyle(.bordered)
                                Button("使用云端", role: .destructive) { useRemote(conflict) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("云端数据") {
                Button("删除 iCloud 中的同步快照", role: .destructive) {
                    showingDeleteCloudConfirmation = true
                }
                .disabled(isWorking)
            }
        }
        .navigationTitle("iCloud 私有同步")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkAvailability() }
        .onChange(of: isEnabled) { _, enabled in
            if enabled { startSync() }
        }
        .confirmationDialog(
            "删除云端同步快照？",
            isPresented: $showingDeleteCloudConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除云端数据", role: .destructive, action: deleteCloudData)
            Button("取消", role: .cancel) {}
        } message: {
            Text("不会删除本机账本。之后重新开启同步时，会将本机数据作为新的云端起点。")
        }
        .alert("同步失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    private func checkAvailability() async {
        switch await CloudSyncService().availability() {
        case .available: availability = "可用"
        case .unavailable(let reason): availability = reason
        }
    }

    private func startSync() {
        guard isEnabled, !isWorking else { return }
        isWorking = true
        Task {
            do {
                let result = try await CloudSyncService().synchronize(
                    context: context,
                    baseCurrencyCode: baseCurrencyCode
                )
                statusMessage = result.message
            } catch {
                UserDefaults.standard.set(error.localizedDescription, forKey: CloudSyncService.lastErrorKey)
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func keepLocal(_ conflict: CloudSyncConflictCopy) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                try await CloudSyncService().resolveKeepingLocal(
                    conflict,
                    context: context,
                    baseCurrencyCode: baseCurrencyCode
                )
                statusMessage = "已保留本机版本并更新云端"
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func useRemote(_ conflict: CloudSyncConflictCopy) {
        guard !isWorking else { return }
        isWorking = true
        do {
            let settings = try CloudSyncService().resolveUsingRemote(
                conflict,
                context: context,
                currentBaseCurrencyCode: baseCurrencyCode
            )
            baseCurrencyCode = settings.baseCurrencyCode
            statusMessage = "已使用冲突副本中的云端版本"
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func deleteCloudData() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                try await CloudSyncService().deleteCloudData()
                statusMessage = "云端同步快照已删除，本机数据未改变"
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
