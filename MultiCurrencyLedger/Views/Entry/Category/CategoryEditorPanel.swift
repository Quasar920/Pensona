import SwiftUI

struct CategoryEditorDraft: Equatable {
    var name: String
    var icon: CategoryIconDraft
}

struct CategoryEditorPanel: View {
    let title: String
    @Binding var draft: CategoryEditorDraft
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.headline)
            TextField("分类名称", text: $draft.name)
                .textFieldStyle(.roundedBorder)
            CategoryIconPicker(draft: $draft.icon)
            HStack(spacing: 12) {
                Button("取消", action: cancel)
                    .buttonStyle(.bordered)
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: 440)
        .ledgerSurface(.centeredActionPanel, cornerRadius: 28)
        .padding(24)
    }
}
