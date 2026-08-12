import SwiftData
import SwiftUI

struct EntryCategoryPager: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var context
    let categories: [LedgerCategory]
    let type: CategoryKind
    @Binding var selectedID: UUID?
    @Binding var isReordering: Bool
    @Binding var isPresentingManagementOverlay: Bool

    @State private var expandedRootID: UUID?
    @State private var actionCategory: LedgerCategory?
    @State private var editor: EditorContext?
    @State private var editorDraft = CategoryEditorDraft(
        name: "",
        icon: CategoryIconDraft(symbolName: "tag", uploadedData: nil, renderingMode: .original)
    )
    @State private var targetAction: TargetAction?
    @State private var pendingDelete: DeleteRequest?
    @State private var errorMessage: String?
    @State private var globalFrame: CGRect = .zero
    @State private var gridGlobalFrame: CGRect = .zero

    private var relevant: [LedgerCategory] {
        categories.filter { $0.type == type && !$0.isArchived }
    }
    private var roots: [LedgerCategory] {
        relevant.filter { $0.parentID == nil }.sorted(by: rootSort)
    }
    private var columns: Int { dynamicTypeSize.isAccessibilitySize ? 3 : 5 }
    private var gridValues: [GridItemValue] { roots.map(GridItemValue.category) + [.add] }
    private var expandedRoot: LedgerCategory? {
        roots.first { $0.id == expandedRootID }
    }
    private var expandedChildren: [LedgerCategory] {
        guard let expandedRootID else { return [] }
        return relevant.filter { $0.parentID == expandedRootID }.sorted(by: categorySort)
    }
    private var overlayBounds: CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds
            ?? CGRect(x: 0, y: 0, width: max(globalFrame.maxX, 1), height: max(globalFrame.maxY, 1))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(type == .expense ? "支出分类" : "收入分类")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if isReordering {
                    Button("完成") {
                        isReordering = false
                        expandedRootID = nil
                    }
                    .font(.caption.weight(.semibold))
                } else if let selected = relevant.first(where: { $0.id == selectedID }) {
                    Text(selected.localizedName(locale: locale)).font(.caption).foregroundStyle(LedgerPalette.ink)
                }
            }

        ZStack {
            pageGrid(gridValues)
                .accessibilityIdentifier("entry-category-pager")
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CategoryGridFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        }
        // Four compact rows keep every expense category above the amount
        // panel and leave room for the iPhone home indicator.
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 360 : 264)
            .animation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.responsive, value: expandedRootID)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CategoryPagerFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        }
        .onPreferenceChange(CategoryPagerFramePreferenceKey.self) { globalFrame = $0 }
        .onPreferenceChange(CategoryGridFramePreferenceKey.self) { gridGlobalFrame = $0 }
        .overlay {
            if let expandedRoot {
                GeometryReader { proxy in
                    let hostFrame = proxy.frame(in: .global)
                    let availableHeight = max(180, overlayBounds.height - 160)

                    ZStack {
                        Color.black.opacity(0.42)
                            .contentShape(Rectangle())
                            .onTapGesture { expandedRootID = nil }

                        EntrySubcategoryOverlay(
                            parent: expandedRoot,
                            children: expandedChildren,
                            selectedID: selectedID,
                            isReordering: isReordering,
                            select: selectChild,
                            add: { beginCreate(parent: expandedRoot) },
                            longPress: showActions,
                            reorder: reorderChild,
                            close: { expandedRootID = nil }
                        )
                        .frame(width: min(360, overlayBounds.width - 36))
                        .frame(height: subcategoryPanelHeight(maximum: availableHeight))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("entry-subcategory-layer")
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                    .frame(width: overlayBounds.width, height: overlayBounds.height)
                    .position(
                        x: overlayBounds.midX - hostFrame.minX,
                        y: overlayBounds.midY - hostFrame.minY
                    )
                }
            }
        }
        .overlay {
            if actionCategory != nil || editor != nil || targetAction != nil {
                ZStack {
                    Color.black.opacity(0.20)
                        .contentShape(Rectangle())
                    if let category = actionCategory {
                        CategoryActionPanel(
                            category: category,
                            edit: { beginEdit(category) },
                            addChild: { beginCreate(parent: category) },
                            changeParent: { targetAction = .move(category); actionCategory = nil },
                            promote: {
                                perform { try service.promoteToRoot(category) }
                                actionCategory = nil
                                isPresentingManagementOverlay = false
                            },
                            delete: { prepareDelete(category) },
                            reorder: { beginReorder(category) },
                            cancel: {
                                actionCategory = nil
                                isPresentingManagementOverlay = false
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                    if editor != nil {
                        CategoryEditorPanel(
                            title: editor?.title ?? AppLocalization.string("分类"),
                            draft: $editorDraft,
                            cancel: {
                                editor = nil
                                isPresentingManagementOverlay = false
                            },
                            save: saveEditor
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                    if let targetAction {
                        targetPanel(targetAction)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
                .frame(width: overlayBounds.width, height: overlayBounds.height)
                .position(
                    x: overlayBounds.midX - globalFrame.minX,
                    y: overlayBounds.midY - globalFrame.minY
                )
            }
        }
        .animation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.responsive, value: actionCategory?.id)
        .confirmationDialog(
            pendingDelete?.title ?? AppLocalization.string("删除分类？"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let request = pendingDelete else { return }
                perform { try service.delete(request.category, migratingReferencesTo: request.target) }
                pendingDelete = nil
                targetAction = nil
                isPresentingManagementOverlay = false
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.message ?? "")
        }
        .alert("分类操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
        .onChange(of: type) { _, _ in
            expandedRootID = nil
            isReordering = false
            isPresentingManagementOverlay = false
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["ENTRY_PREVIEW_SUBCATEGORY"] == "1" {
                expandedRootID = roots.first?.id
            }
            if ProcessInfo.processInfo.environment["ENTRY_PREVIEW_ACTION"] == "1" {
                actionCategory = roots.first
                isPresentingManagementOverlay = true
            }
            if ProcessInfo.processInfo.environment["ENTRY_PREVIEW_REORDER"] == "1" {
                isReordering = true
            }
            #endif
        }
        .zIndex(expandedRootID == nil ? 0 : 1_000)
    }

    private var service: CategoryService { CategoryService(context: context) }

    @ViewBuilder
    private func pageGrid(_ values: [GridItemValue]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                categoryGrid(values)
                    .padding(.bottom, 12)
            }
            .scrollIndicators(.visible)
        } else {
            categoryGrid(values)
        }
    }

    private func categoryGrid(_ values: [GridItemValue]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns),
            spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 4
        ) {
            ForEach(values) { value in
                switch value {
                case let .category(category): rootTile(category)
                case .add: addRootTile
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 0)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func rootTile(_ category: LedgerCategory) -> some View {
        let selectedRootID = relevant.first(where: { $0.id == selectedID })?.parentID ?? selectedID
        return Button { selectRoot(category) } label: {
            VStack(spacing: 4) {
                CategoryIconImage(category: category, size: dynamicTypeSize.isAccessibilitySize ? 48 : 36)
                Text(category.localizedName(locale: locale))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.62 : 0.72)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(selectedRootID == category.id ? LedgerPalette.accent : EntryCategoryAppearance.ink)
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 88 : 62)
            .background(
                EntryCategoryAppearance.card,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(selectedRootID == category.id ? LedgerPalette.ink.opacity(0.75) : .clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(LedgerGlassPressStyle())
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 1)
                .onEnded { _ in showActions(category) }
        )
        .categoryReorderable(isEnabled: isReordering, itemID: category.id) { items in
            guard isReordering, let raw = items.first, let sourceID = UUID(uuidString: raw) else { return false }
            reorderRoot(sourceID, category.id)
            return true
        }
        .rotationEffect(isReordering ? .degrees(category.id.uuidString.hashValue.isMultiple(of: 2) ? 1.2 : -1.2) : .zero)
        .animation(
            isReordering ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .default,
            value: isReordering
        )
    }

    private var addRootTile: some View {
        Button { beginCreate(parent: nil) } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 30 : 32, weight: .medium))
                    .foregroundStyle(LedgerPalette.accent)
                Text("新分类").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(EntryCategoryAppearance.ink)
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 88 : 62)
            .background(
                EntryCategoryAppearance.card,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(LedgerGlassPressStyle())
    }

    private func rootSort(_ lhs: LedgerCategory, _ rhs: LedgerCategory) -> Bool {
        // “兜底” is deliberately the final expense category, even if a user
        // has added other root categories later.
        let fallbackKey = "category.expense.fallback"
        if lhs.systemLocalizationKey == fallbackKey { return false }
        if rhs.systemLocalizationKey == fallbackKey { return true }
        return categorySort(lhs, rhs)
    }

    private func selectRoot(_ category: LedgerCategory) {
        if isReordering {
            if relevant.contains(where: { $0.parentID == category.id }) { expandedRootID = category.id }
            return
        }
        selectedID = category.id
        if relevant.contains(where: { $0.parentID == category.id }) {
            expandedRootID = category.id
        }
    }

    private func selectChild(_ category: LedgerCategory) {
        guard !isReordering else { return }
        selectedID = category.id
        expandedRootID = nil
    }

    private func showActions(_ category: LedgerCategory) {
        guard !isReordering else { return }
        HapticFeedbackService().impact(.medium)
        actionCategory = category
        isPresentingManagementOverlay = true
    }

    private func beginCreate(parent: LedgerCategory?) {
        actionCategory = nil
        isPresentingManagementOverlay = true
        editor = .create(parent: parent)
        editorDraft = CategoryEditorDraft(
            name: "",
            icon: CategoryIconDraft(symbolName: parent?.symbolName ?? "tag", uploadedData: nil, renderingMode: .original)
        )
    }

    private func beginEdit(_ category: LedgerCategory) {
        actionCategory = nil
        isPresentingManagementOverlay = true
        editor = .edit(category)
        editorDraft = CategoryEditorDraft(
            name: category.localizedName(locale: locale),
            icon: CategoryIconDraft(
                symbolName: category.symbolName,
                uploadedData: nil,
                renderingMode: .original,
                keepsExistingUpload: category.iconSource == .userUploaded
            )
        )
    }

    private func saveEditor() {
        guard let editor else { return }
        do {
            switch editor {
            case let .create(parent):
                let category = try service.create(
                    name: editorDraft.name,
                    type: type,
                    symbolName: editorDraft.icon.symbolName,
                    bookID: UUID(),
                    parent: parent
                )
                if let data = editorDraft.icon.uploadedData {
                    do {
                        let stored = try CategoryIconStore().saveImage(
                            data,
                            categoryID: category.id,
                            renderingMode: editorDraft.icon.renderingMode
                        )
                        try service.updateNameAndIcon(
                            category,
                            name: editorDraft.name,
                            symbolName: editorDraft.icon.symbolName,
                            iconSource: .userUploaded,
                            userIconRelativePath: stored.thumbnailRelativePath
                        )
                    } catch {
                        try? service.delete(category)
                        throw error
                    }
                }
                selectedID = category.id
            case let .edit(category):
                var source: CategoryIconSource = .builtIn
                var path: String?
                if editorDraft.icon.keepsExistingUpload {
                    source = .userUploaded
                    path = category.userIconRelativePath
                } else if let data = editorDraft.icon.uploadedData {
                    let stored = try CategoryIconStore().saveImage(
                        data,
                        categoryID: category.id,
                        renderingMode: editorDraft.icon.renderingMode
                    )
                    source = .userUploaded
                    path = stored.thumbnailRelativePath
                }
                try service.updateNameAndIcon(
                    category,
                    name: editorDraft.name,
                    symbolName: editorDraft.icon.symbolName,
                    iconSource: source,
                    userIconRelativePath: path
                )
            }
            self.editor = nil
            isPresentingManagementOverlay = false
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func beginReorder(_ category: LedgerCategory) {
        actionCategory = nil
        isReordering = true
        isPresentingManagementOverlay = false
        if let parentID = category.parentID { expandedRootID = parentID }
    }

    private func reorderRoot(_ sourceID: UUID, _ targetID: UUID) {
        let reordered = CategoryReorderMode.moving(sourceID: sourceID, before: targetID, in: roots)
        perform { try service.reorder(reordered) }
    }

    private func reorderChild(_ sourceID: UUID, _ targetID: UUID) {
        let reordered = CategoryReorderMode.moving(sourceID: sourceID, before: targetID, in: expandedChildren)
        perform { try service.reorder(reordered) }
    }

    private func prepareDelete(_ category: LedgerCategory) {
        actionCategory = nil
        do {
            let summary = try service.usageSummary(for: category)
            if summary.requiresMigration {
                targetAction = .delete(category, summary)
                isPresentingManagementOverlay = true
            } else {
                pendingDelete = DeleteRequest(category: category, target: nil, message: "此操作无法撤销。")
                isPresentingManagementOverlay = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func targetPanel(_ action: TargetAction) -> some View {
        let category = action.category
        let candidates = roots.filter { $0.id != category.id }
        return VStack(spacing: 12) {
            Text(action.title).font(.headline)
            if case let .delete(_, summary) = action {
                Text("历史交易 \(summary.totalTransactionCount) 笔，子分类 \(summary.directChildCount) 个。请选择迁移目标后再删除。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(candidates) { target in
                        Button {
                            switch action {
                            case let .move(source):
                                perform {
                                    if source.parentID == nil { try service.convertRootToChild(source, under: target) }
                                    else { try service.moveChild(source, to: target) }
                                }
                                targetAction = nil
                                isPresentingManagementOverlay = false
                            case let .delete(source, summary):
                                pendingDelete = DeleteRequest(
                                    category: source,
                                    target: target,
                                    message: "将迁移 \(summary.totalTransactionCount) 笔历史交易和 \(summary.directChildCount) 个子分类，然后删除。"
                                )
                            }
                        } label: {
                            Label(target.localizedName(locale: locale), systemImage: target.symbolName)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxHeight: 280)
            Button("取消") {
                targetAction = nil
                isPresentingManagementOverlay = false
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(maxWidth: 360)
        .ledgerSurface(.centeredActionPanel, cornerRadius: 28)
        .padding(24)
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func categorySort(_ lhs: LedgerCategory, _ rhs: LedgerCategory) -> Bool {
        lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
    }

    private func subcategoryPanelHeight(maximum: CGFloat) -> CGFloat {
        let itemCount = expandedChildren.count + 1
        let rowCount = max(1, Int(ceil(Double(itemCount) / Double(columns == 3 ? 2 : 4))))
        let tileHeight: CGFloat = 64
        let rowSpacing: CGFloat = 12
        let headerAndPadding: CGFloat = 80
        let gridHeight = CGFloat(rowCount) * tileHeight
            + CGFloat(max(0, rowCount - 1)) * rowSpacing
        return min(maximum, headerAndPadding + gridHeight)
    }
}

enum EntryCategoryAppearance {
    /// Keep the sampled light card grey while using the requested dark preview.
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 65 / 255, green: 65 / 255, blue: 66 / 255, alpha: 1)
            : UIColor(red: 227 / 255, green: 227 / 255, blue: 227 / 255, alpha: 1)
    })
    static let overlay = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.045, alpha: 1)
            : UIColor(red: 246 / 255, green: 246 / 255, blue: 246 / 255, alpha: 1)
    })
    static let darkInk = Color(red: 229 / 255, green: 229 / 255, blue: 231 / 255)
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 229 / 255, green: 229 / 255, blue: 231 / 255, alpha: 1)
            : UIColor(white: 0.04, alpha: 1)
    })
}

private enum GridItemValue: Identifiable {
    case category(LedgerCategory)
    case add

    var id: String {
        switch self {
        case let .category(category): category.id.uuidString
        case .add: "add"
        }
    }
}

private enum EditorContext {
    case create(parent: LedgerCategory?)
    case edit(LedgerCategory)

    var title: String {
        switch self {
        case let .create(parent):
            parent == nil ? AppLocalization.string( "新建主分类") : AppLocalization.string( "新建子分类")
        case .edit: AppLocalization.string( "修改分类")
        }
    }
}

private enum TargetAction {
    case move(LedgerCategory)
    case delete(LedgerCategory, CategoryUsageSummary)

    var category: LedgerCategory {
        switch self {
        case let .move(category), let .delete(category, _): category
        }
    }
    var title: String {
        switch self {
        case let .move(category):
            category.parentID == nil
                ? AppLocalization.string( "改为哪个分类的子分类？")
                : AppLocalization.string( "迁移至哪个主分类？")
        case .delete: AppLocalization.string( "迁移引用后删除")
        }
    }
}

private struct DeleteRequest {
    let category: LedgerCategory
    let target: LedgerCategory?
    let message: String
    var title: String { AppLocalization.string( "删除“\(category.localizedName())”？") }
}

private struct CategoryPagerFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct CategoryGridFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
