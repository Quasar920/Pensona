import SwiftUI

struct CategoryActionPanel: View {
    @Environment(\.locale) private var locale
    let category: LedgerCategory
    let edit: () -> Void
    let addChild: () -> Void
    let changeParent: () -> Void
    let promote: () -> Void
    let delete: () -> Void
    let reorder: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(category.localizedName(locale: locale)).font(.headline).padding(.bottom, 4)
            action("修改", symbol: "pencil", edit)
            if category.parentID == nil {
                action("添加子分类", symbol: "plus", addChild)
                action("改为子分类", symbol: "arrow.turn.down.right", changeParent)
            } else {
                action("迁移至其他分类", symbol: "arrowshape.turn.up.right", changeParent)
                action("改为主分类", symbol: "arrow.up.to.line", promote)
            }
            action("删除", symbol: "trash", role: .destructive, delete)
            action("排序", symbol: "arrow.up.arrow.down", reorder)
            Button("取消", action: cancel)
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: 320)
        .ledgerSurface(.centeredActionPanel, cornerRadius: 28)
        .padding(24)
    }

    private func action(
        _ title: String,
        symbol: String,
        role: ButtonRole? = nil,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }
}
