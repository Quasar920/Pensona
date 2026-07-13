import SwiftUI

struct MigrationRecoveryView: View {
    @State private var snapshots = PersistentStoreSnapshotService.snapshots()
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Text("Schema 版本更新前会复制 SwiftData 数据库及 WAL/SHM。选择恢复后，需要从系统任务切换器完全关闭 App 并重新打开，恢复才会在数据库打开前执行。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let pending = PersistentStoreSnapshotService.pendingRestore() {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("已预约下次启动恢复", systemImage: "clock.arrow.circlepath")
                        Text(URL(fileURLWithPath: pending).lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                        Button("取消预约", role: .destructive) {
                            PersistentStoreSnapshotService.cancelPendingRestore()
                            message = "已取消预约恢复"
                        }
                    }
                }
            }
            Section("迁移快照") {
                if snapshots.isEmpty {
                    Text("当前没有迁移快照").foregroundStyle(.secondary)
                }
                ForEach(snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.title).font(.headline)
                        Text(snapshot.directoryURL.lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("下次启动恢复") {
                                PersistentStoreSnapshotService.requestRestore(snapshot)
                                message = "已预约恢复。请完全关闭并重新打开 App。"
                            }
                            ShareLink(item: snapshot.directoryURL) {
                                Label("导出", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("迁移恢复")
        .navigationBarTitleDisplayMode(.inline)
        .alert("迁移恢复", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) { Button("好") {} } message: { Text(message ?? "") }
    }
}
