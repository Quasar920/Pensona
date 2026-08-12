import SwiftData
import SwiftUI

/// A full-screen, stateful bill search. It deliberately owns its temporary
/// query state: dismissing it creates a fresh initial search next time, while
/// navigating to detail/category pages leaves the state untouched.
struct BillSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("billSearch.recentKeywords") private var recentKeywordsStorage = "[]"

    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: [Account]
    @Query private var relations: [TransactionRelation]
    @Query private var settlements: [AASettlement]
    @Query private var aaSplits: [AASplit]

    @FocusState private var keywordFocused: Bool
    /// Kept separate from the submitted query so SwiftUI never replaces the
    /// text field's in-progress composition while a delayed search completes.
    @State private var keywordInput = ""
    @State private var query = BillSearchQuery()
    @State private var result: BillSearchResult?
    @State private var loadedCount = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var filterPresentation = SearchFilterPresentationState()
    @State private var filterTagFrames: [SearchFilterPanel: CGRect] = [:]
    @State private var isCustomTimeFilter = false
    @State private var keywordTask: Task<Void, Never>?
    @State private var isHeaderVisible = true
    @State private var previousScrollOffset: CGFloat = 0
    @State private var upwardTravel: CGFloat = 0
    @State private var showAllRecent = false
    @State private var confirmingClearRecent = false
    @State private var transientMessage: String?

    private let pageSize = 50
    private let service = BillSearchService()

    private var recentKeywords: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(recentKeywordsStorage.utf8))) ?? []
    }

    private var loadedTransactions: [LedgerTransaction] {
        result?.page(offset: 0, size: loadedCount) ?? []
    }

    private var hasMore: Bool { loadedCount < (result?.totalCount ?? 0) }
    private var isInitialState: Bool { !query.hasSearchCriteria && result == nil && !isLoading }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                HomePalette.background.ignoresSafeArea()
                searchContent
                    .padding(.top, isHeaderVisible ? headerHeight : 0)

                if isHeaderVisible {
                    header
                        .transition(.move(edge: .top))
                }

                if let transientMessage {
                    Text(transientMessage)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeOut(duration: 0.2), value: isHeaderVisible)
            .navigationDestination(for: LedgerTransaction.self) { transaction in
                TransactionDetailView(transaction: transaction)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(for: BillSearchDynamicCategory.self) { category in
                if let result {
                    BillSearchCategoryView(
                        category: category,
                        transactions: service.transactions(
                            for: category, in: result, relations: relations, settlements: settlements
                        ),
                        relations: relations,
                        settlements: settlements,
                        summary: result.dynamicSummaries.first { $0.category == category }
                    )
                }
            }
            .overlay {
                GeometryReader { proxy in
                    searchFilterOverlay(in: proxy)
                }
            }
            .coordinateSpace(name: SearchFilterCoordinateSpace.name)
            .onPreferenceChange(SearchFilterTagFramePreferenceKey.self) { filterTagFrames = $0 }
            .alert("清空最近搜索？", isPresented: $confirmingClearRecent) {
                Button("清空", role: .destructive) { saveRecentKeywords([]) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会删除所有最近搜索记录。")
            }
            .alert("金额范围无效", isPresented: Binding(
                get: { loadError == "金额范围无效" },
                set: { if !$0 { loadError = nil } }
            )) { Button("好") {} } message: {
                Text("最低金额不能大于最高金额。")
            }
            .task {
                keywordFocused = true
            }
            .onChange(of: keywordFocused) { _, focused in
                if focused { isHeaderVisible = true }
            }
            .onChange(of: filterPresentation.phase) { _, phase in
                if phase != .closed { isHeaderVisible = true }
            }
            .onChange(of: transactions.count) { _, _ in
                guard result != nil else { return }
                reloadImmediately()
            }
        }
    }

    private var headerHeight: CGFloat { 116 }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索账单", text: $keywordInput)
                        .focused($keywordFocused)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit {
                            keywordFocused = false
                            executeExplicitSearch()
                        }
                        .onChange(of: keywordInput) { _, _ in scheduleKeywordSearch() }
                    if !keywordInput.isEmpty {
                        Button {
                            keywordInput = ""
                            query.keyword = ""
                            keywordFocused = false
                            if query.hasSearchCriteria { reloadImmediately() }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("清除关键词")
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 46)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())

                Button("取消", action: exitSearch)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize()
            }
            HStack(spacing: 8) {
                filterButton(.time, title: query.timeRange.title)
                filterButton(.amount, title: amountTitle)
                filterButton(.book, title: bookTitle)
                filterButton(.account, title: accountTitle)
                filterButton(.sort, title: query.sortMode.compactTitle)
            }
        }
        .padding(.horizontal, LedgerLayout.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(HomePalette.background)
    }

    private func filterButton(_ panel: SearchFilterPanel, title: String) -> some View {
        let selected = isPanelSelected(panel)
        return Button {
            guard !filterPresentation.isActive else { return }
            if keywordFocused && !keywordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                executeQuery(saveKeyword: false)
            }
            keywordFocused = false
            presentFilter(panel, title: title)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(selected ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemBackground), in: Capsule())
                .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .opacity(filterPresentation.isTransitioning && filterPresentation.panel == panel ? 0 : 1)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchFilterTagFramePreferenceKey.self,
                    value: [panel: proxy.frame(in: .named(SearchFilterCoordinateSpace.name))]
                )
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if isInitialState {
                    initialContent
                } else if isLoading {
                    ProgressView("正在加载")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let result {
                    resultContent(result)
                } else if loadError != nil {
                    VStack(spacing: 10) {
                        Text("加载失败").font(.headline)
                        Button("重新加载", action: reloadImmediately)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(.horizontal, LedgerLayout.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, RootEntryLayout.scrollContentClearance)
        }
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, offset in
            handleScroll(offset: offset)
        }
        .simultaneousGesture(TapGesture().onEnded { keywordFocused = false })
    }

    @ViewBuilder
    private var initialContent: some View {
        if recentKeywords.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("搜索账单").font(.headline)
                Text("可输入备注、分类、账户或账本名称，也可以使用上方筛选条件。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 36)
        } else {
            HStack {
                Text("最近搜索").font(.headline)
                Spacer()
                Button("清空") { confirmingClearRecent = true }
                    .font(.subheadline)
            }
            recentCards
        }
    }

    private var recentCards: some View {
        let visible = showAllRecent ? recentKeywords : Array(recentKeywords.prefix(6))
        return VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 10) {
                ForEach(visible, id: \.self) { keyword in
                    Button { useRecentKeyword(keyword) } label: {
                        Text(keyword)
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.leading, 12)
                            .padding(.trailing, 28)
                            .frame(height: 36)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                            .overlay(alignment: .topTrailing) {
                                Button { deleteRecentKeyword(keyword) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 18, height: 18)
                                        .background(Color(uiColor: .secondarySystemBackground).opacity(0.72), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 3, y: -3)
                                .accessibilityLabel("删除 \(keyword)")
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            if recentKeywords.count > 6 {
                Button(showAllRecent ? "收起" : "展开") { showAllRecent.toggle() }
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private func resultContent(_ result: BillSearchResult) -> some View {
        SearchSummaryView(result: result, currencyCode: baseCurrencyCode)
        if !result.dynamicSummaries.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(result.dynamicSummaries) { summary in
                        NavigationLink(value: summary.category) {
                            DynamicSummaryCard(summary: summary, currencyCode: baseCurrencyCode)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded(saveCurrentKeyword))
                    }
                }
                .padding(.vertical, 2)
            }
        }

        if result.totalCount == 0 {
            VStack(spacing: 12) {
                Text("没有找到相关账单").font(.headline)
                Button("重置全部条件", action: resetAllConditions)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if query.sortMode.usesDayGrouping {
            ForEach(dayGroups(loadedTransactions), id: \.date) { group in
                transactionGroup(group.date, transactions: group.transactions)
            }
            loadingFooter
        } else {
            ForEach(loadedTransactions) { transaction in
                NavigationLink(value: transaction) {
                    SearchResultRow(transaction: transaction, alwaysShowsDate: true)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded(saveCurrentKeyword))
                .onAppear { if transaction.id == loadedTransactions.last?.id { loadMoreIfNeeded() } }
            }
            loadingFooter
        }
    }

    @ViewBuilder
    private func transactionGroup(_ date: Date, transactions: [LedgerTransaction]) -> some View {
        HStack {
            Text(date.dayHeading(locale: locale)).font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(transactions.count) 笔").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 6)
        ForEach(transactions) { transaction in
            NavigationLink(value: transaction) {
                SearchResultRow(transaction: transaction, alwaysShowsDate: false)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded(saveCurrentKeyword))
            .onAppear { if transaction.id == loadedTransactions.last?.id { loadMoreIfNeeded() } }
        }
    }

    @ViewBuilder
    private var loadingFooter: some View {
        if isLoadingMore {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
        } else if hasMore {
            Color.clear.frame(height: 20).onAppear(perform: loadMoreIfNeeded)
        }
    }

    @ViewBuilder
    private func filterSheet(_ panel: SearchFilterPanel) -> some View {
        switch panel {
        case .time:
            SearchTimeFilterView(
                current: query.timeRange,
                showingCustom: $isCustomTimeFilter,
                cancel: dismissFilter
            ) { range in
                query.timeRange = range
                reloadImmediately()
                dismissFilter()
            }
        case .amount:
            SearchAmountFilterView(
                minimum: query.minimumAmount,
                maximum: query.maximumAmount,
                cancel: dismissFilter
            ) { minimum, maximum in
                guard minimum == nil || maximum == nil || minimum! <= maximum! else {
                    loadError = "金额范围无效"
                    return
                }
                query.minimumAmount = minimum
                query.maximumAmount = maximum
                reloadImmediately()
                dismissFilter()
            }
        case .book:
            SearchBookFilterView(books: books, selectedID: query.bookID, cancel: dismissFilter) { id in
                applyBook(id)
                dismissFilter()
            }
        case .account:
            SearchAccountFilterView(
                accounts: availableAccounts,
                selectedIDs: query.accountIDs,
                cancel: dismissFilter
            ) { ids in
                query.accountIDs = ids
                reloadImmediately()
                dismissFilter()
            }
        case .sort:
            SearchSortFilterView(selected: query.sortMode, cancel: dismissFilter) { mode in
                query.sortMode = mode
                reloadImmediately()
                dismissFilter()
            }
        }
    }

    @ViewBuilder
    private func searchFilterOverlay(in proxy: GeometryProxy) -> some View {
        if let panel = filterPresentation.panel {
            let sourceFrame = filterPresentation.sourceFrame
            let targetFrame = filterPanelTargetFrame(
                for: panel,
                canvasSize: proxy.size,
                sourceFrame: sourceFrame
            )
            ZStack(alignment: .topLeading) {
                if filterPresentation.phase == .presented {
                    SearchFilterPanelSurface(content: filterSheet(panel))
                        .frame(width: targetFrame.width, height: targetFrame.height)
                        .position(x: targetFrame.midX, y: targetFrame.midY)
                        .transition(.identity)
                }

                if filterPresentation.isTransitioning {
                    SearchFilterPanelSurface(showsShadow: false, content: SearchFilterTransitionPanel(
                        panel: panel,
                        isCustomTimeFilter: isCustomTimeFilter,
                        timeRange: query.timeRange,
                        minimumAmount: query.minimumAmount,
                        maximumAmount: query.maximumAmount,
                        books: books,
                        selectedBookID: query.bookID,
                        accounts: availableAccounts,
                        selectedAccountIDs: query.accountIDs,
                        sortMode: query.sortMode
                    ))
                        .frame(width: targetFrame.width, height: targetFrame.height)
                        .position(x: targetFrame.midX, y: targetFrame.midY)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .searchFilterGenieLayer(
                            progress: filterPresentation.progress,
                            panelFrame: targetFrame,
                            tagFrame: sourceFrame,
                            canvasSize: proxy.size,
                            reduceMotion: reduceMotion
                        )
                        // Apply the shadow after deformation so it follows the
                        // rounded Genie silhouette. At progress zero it is
                        // pixel-compatible with the live panel's shadow,
                        // preventing a final-frame shadow pop.
                        .shadow(
                            color: .black.opacity(0.15 * (1 - filterPresentation.progress)),
                            radius: 22 * CGFloat(1 - filterPresentation.progress),
                            y: 10 * CGFloat(1 - filterPresentation.progress)
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.identity)
                }

                if filterPresentation.isTransitioning, !sourceFrame.isEmpty {
                    SearchFilterSourceChip(title: filterPresentation.sourceTitle)
                        .frame(width: sourceFrame.width, height: sourceFrame.height)
                        .position(x: sourceFrame.midX, y: sourceFrame.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .allowsHitTesting(filterPresentation.phase == .presented)
                    .onTapGesture(perform: dismissFilter)
            }
            .animation(.easeInOut(duration: 0.24), value: isCustomTimeFilter)
        }
    }

    private func filterPanelTargetFrame(
        for panel: SearchFilterPanel,
        canvasSize: CGSize,
        sourceFrame: CGRect
    ) -> CGRect {
        let horizontalInset: CGFloat = 16
        let outerPadding: CGFloat = 16
        let headerHeight: CGFloat = 48
        let rowHeight: CGFloat = 50
        let preferredHeight: CGFloat
        switch panel {
        case .time:
            preferredHeight = outerPadding * 2 + headerHeight
                + rowHeight * CGFloat(isCustomTimeFilter ? 2 : 6)
        case .amount:
            preferredHeight = outerPadding * 2 + headerHeight + rowHeight * 3
        case .book:
            preferredHeight = outerPadding * 2 + headerHeight
                + rowHeight * CGFloat(1 + books.count)
        case .account:
            let grouped = Dictionary(grouping: availableAccounts, by: { $0.type.assetGroup })
            let groupHeaders = CGFloat(grouped.keys.count) * 26
            let actionBar: CGFloat = 62
            preferredHeight = outerPadding * 2 + headerHeight + groupHeaders
                + rowHeight * CGFloat(availableAccounts.count) + actionBar
        case .sort:
            preferredHeight = outerPadding * 2 + headerHeight
                + rowHeight * CGFloat(BillSearchSortMode.allCases.count)
        }
        let height = min(preferredHeight, max(230, canvasSize.height - 92))
        let width = min(320, max(280, canvasSize.width * 0.78))
        let x = min(
            max(horizontalInset, sourceFrame.minX),
            canvasSize.width - width - horizontalInset
        )
        let y = min(
            max(8, sourceFrame.maxY + 10),
            max(8, canvasSize.height - height - 8)
        )
        return CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    private func presentFilter(_ panel: SearchFilterPanel, title: String) {
        guard let sourceFrame = filterTagFrames[panel], !sourceFrame.isEmpty else { return }
        if panel == .time { isCustomTimeFilter = false }
        filterPresentation.prepare(panel: panel, sourceFrame: sourceFrame, sourceTitle: title)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(17))
            guard filterPresentation.phase == .opening else { return }
            withAnimation(filterTransitionAnimation) {
                filterPresentation.progress = 0
            } completion: {
                guard filterPresentation.phase == .opening else { return }
                filterPresentation.finishOpening()
            }
        }
    }

    private func dismissFilter() {
        guard filterPresentation.phase == .presented else { return }
        filterPresentation.beginClosing()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(17))
            guard filterPresentation.phase == .closing else { return }
            withAnimation(filterTransitionAnimation) {
                filterPresentation.progress = 1
            } completion: {
                guard filterPresentation.phase == .closing else { return }
                filterPresentation.reset()
            }
        }
    }

    private var filterTransitionAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.20)
        }
        return filterPresentation.phase == .opening
            ? .spring(response: 0.42, dampingFraction: 0.70)
            : .timingCurve(0.20, 0.72, 0.24, 1, duration: 0.24)
    }

    private var availableAccounts: [Account] {
        let active = accounts.filter { !$0.isArchived }
        guard let bookID = query.bookID else { return active }
        let IDs = Set(transactions.filter { $0.bookID == bookID }.flatMap {
            [$0.sourceAccount?.id, $0.destinationAccount?.id].compactMap { $0 }
        })
        return active.filter { IDs.contains($0.id) }
    }

    private var amountTitle: String {
        switch (query.minimumAmount, query.maximumAmount) {
        case (nil, nil): "金额"
        case let (minimum?, nil): "\(MoneyFormatter.plain(minimum, currencyCode: baseCurrencyCode)) 以上"
        case let (nil, maximum?): "\(MoneyFormatter.plain(maximum, currencyCode: baseCurrencyCode)) 以下"
        case let (minimum?, maximum?): "\(MoneyFormatter.plain(minimum, currencyCode: baseCurrencyCode))～\(MoneyFormatter.plain(maximum, currencyCode: baseCurrencyCode))"
        }
    }

    private var bookTitle: String { query.bookID.flatMap { id in books.first { $0.id == id }?.name } ?? "账本" }
    private var accountTitle: String {
        if query.accountIDs.isEmpty { return "账户" }
        if query.accountIDs.count > 1 { return "\(query.accountIDs.count) 个账户" }
        return accounts.first { query.accountIDs.contains($0.id) }?.name ?? "账户"
    }

    private func isPanelSelected(_ panel: SearchFilterPanel) -> Bool {
        switch panel {
        case .time: query.timeRange != .all
        case .amount: query.minimumAmount != nil || query.maximumAmount != nil
        case .book: query.bookID != nil
        case .account: !query.accountIDs.isEmpty
        case .sort: query.sortMode != .dateDescending
        }
    }

    private func scheduleKeywordSearch() {
        keywordTask?.cancel()
        query.keyword = keywordInput
        guard !query.normalizedTokens.isEmpty else {
            if !query.hasSearchCriteria { result = nil; loadedCount = 0; isLoading = false }
            else { reloadImmediately() }
            return
        }
        keywordTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run { executeQuery(saveKeyword: false) }
        }
    }

    private func executeExplicitSearch() {
        executeQuery(saveKeyword: true)
    }

    private func reloadImmediately() {
        keywordTask?.cancel()
        executeQuery(saveKeyword: false)
    }

    private func executeQuery(saveKeyword: Bool) {
        query.keyword = keywordInput
        guard query.hasSearchCriteria else { result = nil; loadedCount = 0; return }
        isHeaderVisible = true
        result = nil
        loadedCount = 0
        isLoading = false
        isLoading = true
        loadError = nil
        let queryAtStart = query
        Task { @MainActor in
            await Task.yield()
            guard queryAtStart == query else { return }
            let next = service.search(
                transactions: transactions,
                books: books,
                relations: relations,
                settlements: settlements,
                aaSplits: aaSplits,
                query: queryAtStart
            )
            guard queryAtStart == query else { return }
            result = next
            loadedCount = min(pageSize, next.totalCount)
            isLoading = false
            if saveKeyword, !queryAtStart.normalizedKeyword.isEmpty { saveRecentKeyword(queryAtStart.normalizedKeyword) }
        }
    }

    private func loadMoreIfNeeded() {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        Task { @MainActor in
            await Task.yield()
            loadedCount = min(loadedCount + pageSize, result?.totalCount ?? 0)
            isLoadingMore = false
        }
    }

    private func applyBook(_ bookID: UUID?) {
        query.bookID = bookID
        let availableIDs = Set(availableAccounts.map(\.id))
        let removed = query.accountIDs.subtracting(availableIDs)
        query.accountIDs.formIntersection(availableIDs)
        if !removed.isEmpty {
            transientMessage = query.accountIDs.isEmpty
                ? "已清除与当前账本无关联的账户筛选"
                : "已移除 \(removed.count) 个与当前账本无关联的账户"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                transientMessage = nil
            }
        }
        reloadImmediately()
    }

    private func resetAllConditions() {
        keywordTask?.cancel()
        query.reset()
        keywordInput = ""
        result = nil
        loadedCount = 0
        keywordFocused = true
        isHeaderVisible = true
    }

    private func exitSearch() {
        keywordTask?.cancel()
        dismiss()
    }

    private func useRecentKeyword(_ keyword: String) {
        keywordTask?.cancel()
        keywordInput = keyword
        query.keyword = keyword
        keywordFocused = false
        executeQuery(saveKeyword: false)
    }

    private func saveRecentKeyword(_ keyword: String) {
        saveRecentKeywords(([keyword] + recentKeywords.filter { $0 != keyword }).prefix(10).map { $0 })
    }

    private func saveCurrentKeyword() {
        guard !query.normalizedKeyword.isEmpty else { return }
        saveRecentKeyword(query.normalizedKeyword)
    }

    private func deleteRecentKeyword(_ keyword: String) {
        saveRecentKeywords(recentKeywords.filter { $0 != keyword })
        if recentKeywords.count <= 6 { showAllRecent = false }
    }

    private func saveRecentKeywords(_ values: [String]) {
        recentKeywordsStorage = String(data: (try? JSONEncoder().encode(values)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    private func dayGroups(_ items: [LedgerTransaction]) -> [(date: Date, transactions: [LedgerTransaction])] {
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }
        return groups.map { ($0.key, $0.value) }.sorted {
            query.sortMode == .dateAscending ? $0.date < $1.date : $0.date > $1.date
        }
    }

    private func handleScroll(offset: CGFloat) {
        guard !keywordFocused, !filterPresentation.isActive else { isHeaderVisible = true; return }
        let change = offset - previousScrollOffset
        defer { previousScrollOffset = offset }
        if offset <= 0 { isHeaderVisible = true; upwardTravel = 0; return }
        if change > 4 { isHeaderVisible = false; upwardTravel = 0 }
        else if change < -1 {
            upwardTravel += -change
            if upwardTravel >= 20 { isHeaderVisible = true; upwardTravel = 0 }
        }
    }
}

private enum SearchFilterPanel: String, Identifiable, Hashable {
    case time, amount, book, account, sort
    var id: String { rawValue }
}

private enum SearchFilterCoordinateSpace {
    static let name = "bill-search-filter"
}

private struct SearchFilterTagFramePreferenceKey: PreferenceKey {
    static var defaultValue: [SearchFilterPanel: CGRect] = [:]

    static func reduce(value: inout [SearchFilterPanel: CGRect], nextValue: () -> [SearchFilterPanel: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum SearchFilterPresentationPhase: Equatable {
    case closed, opening, presented, closing
}

private struct SearchFilterPresentationState {
    var panel: SearchFilterPanel?
    var phase: SearchFilterPresentationPhase = .closed
    var sourceFrame = CGRect.zero
    var sourceTitle = ""
    /// 0 means the panel is fully expanded; 1 is fully gathered into its chip.
    var progress = 1.0

    var isActive: Bool { phase != .closed }
    var isTransitioning: Bool { phase == .opening || phase == .closing }

    mutating func prepare(panel: SearchFilterPanel, sourceFrame: CGRect, sourceTitle: String) {
        self.panel = panel
        self.sourceFrame = sourceFrame
        self.sourceTitle = sourceTitle
        progress = 1
        phase = .opening
    }

    mutating func finishOpening() {
        guard phase == .opening else { return }
        progress = 0
        phase = .presented
    }

    mutating func beginClosing() {
        guard phase == .presented else { return }
        progress = 0
        phase = .closing
    }

    mutating func reset() {
        panel = nil
        phase = .closed
        sourceFrame = .zero
        sourceTitle = ""
        progress = 1
    }
}

private struct SearchFilterPanelSurface<Content: View>: View {
    let content: Content
    let showsShadow: Bool

    init(showsShadow: Bool = true, content: Content) {
        self.content = content
        self.showsShadow = showsShadow
    }

    var body: some View {
        content
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
            }
            .shadow(
                color: .black.opacity(showsShadow ? 0.15 : 0),
                radius: showsShadow ? 22 : 0,
                y: showsShadow ? 10 : 0
            )
    }
}

/// Search filters use the same compact floating-card motion as other
/// source-anchored controls, without a full-panel mesh deformation.
private struct SearchFilterGenieLayerModifier: ViewModifier {
    let progress: Double
    let panelFrame: CGRect
    let tagFrame: CGRect
    let canvasSize: CGSize
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .scaleEffect(1 - 0.03 * CGFloat(progress))
                .opacity(1 - progress)
        } else {
            content
                .scaleEffect(1 - 0.06 * CGFloat(progress))
                .offset(y: 18 * CGFloat(progress))
                .opacity(1 - progress)
        }
    }
}

private extension View {
    func searchFilterGenieLayer(
        progress: Double,
        panelFrame: CGRect,
        tagFrame: CGRect,
        canvasSize: CGSize,
        reduceMotion: Bool
    ) -> some View {
        modifier(SearchFilterGenieLayerModifier(
            progress: progress,
            panelFrame: panelFrame,
            tagFrame: tagFrame,
            canvasSize: canvasSize,
            reduceMotion: reduceMotion
        ))
    }
}

private struct SearchFilterSourceChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
    }
}

/// Render-only SwiftUI facsimile used while the Metal shader is active. Its
/// geometry deliberately shares the live panel's header, row and action-bar
/// components so the final shader frame and first interactive frame coincide.
private struct SearchFilterTransitionPanel: View {
    let panel: SearchFilterPanel
    let isCustomTimeFilter: Bool
    let timeRange: BillSearchTimeRange
    let minimumAmount: Decimal?
    let maximumAmount: Decimal?
    let books: [LedgerBook]
    let selectedBookID: UUID?
    let accounts: [Account]
    let selectedAccountIDs: Set<UUID>
    let sortMode: BillSearchSortMode

    var body: some View {
        VStack(spacing: 0) {
            SearchFilterCardHeader(
                title: title,
                cancel: {},
                confirm: headerConfirmAction
            )
            Divider()
            panelContent
        }
        .searchFilterInnerSurface()
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .time:
            if isCustomTimeFilter {
                dateRow("开始日期", date: customDates.start)
                dateRow("结束日期", date: customDates.end)
                Spacer(minLength: 0)
            } else {
                transitionRow("全部时间", selected: timeRange == .all)
                transitionRow("今天", selected: timeRange == .today)
                transitionRow("本周", selected: timeRange == .thisWeek)
                transitionRow("本月", selected: timeRange == .thisMonth)
                transitionRow("本年", selected: timeRange == .thisYear)
                transitionRow("自定义日期范围", selected: false, trailingSymbol: "chevron.right")
            }
        case .amount:
            transitionField(
                "最低金额",
                value: minimumAmount.map { NSDecimalNumber(decimal: $0).stringValue }
            )
            transitionField(
                "最高金额",
                value: maximumAmount.map { NSDecimalNumber(decimal: $0).stringValue }
            )
            transitionRow("清除金额", selected: false, destructive: true)
        case .book:
            transitionRow("全部账本", selected: selectedBookID == nil, radio: true)
            ForEach(books) { book in
                transitionRow(book.name, selected: selectedBookID == book.id, radio: true)
            }
        case .account:
            // ScrollView/LazyVStack children live in a separate backing layer
            // and disappear when the Metal transition samples this facade on
            // a physical device. Materialize the rows in the sampled layer;
            // the interactive panel restores scrolling after the transition.
            VStack(spacing: 0) {
                ForEach(accountGroups, id: \.0.id) { group, members in
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .padding(.horizontal, 16)
                    ForEach(members) { account in
                        transitionRow(
                            account.name,
                            selected: selectedAccountIDs.contains(account.id),
                            radio: true
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            Divider()
            HStack {
                Button("清空选择") {}
                Spacer()
                Button(confirmationTitle) {}
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
        case .sort:
            ForEach(BillSearchSortMode.allCases) { mode in
                transitionRow(mode.title, selected: sortMode == mode)
            }
        }
    }

    private func transitionRow(
        _ title: String,
        selected: Bool,
        radio: Bool = false,
        trailingSymbol: String? = nil,
        destructive: Bool = false
    ) -> some View {
        SearchFilterActionRow(
            title,
            isSelected: selected,
            usesRadio: radio,
            trailingSymbol: trailingSymbol,
            role: destructive ? .destructive : nil,
            action: {}
        )
    }

    private func transitionField(_ title: String, value: String?) -> some View {
        SearchFilterValueRow {
            Text(value?.isEmpty == false ? value! : title)
                // Match UITextField's native placeholder color used by the
                // interactive amount panel so the handoff does not change
                // the label's apparent weight or opacity.
                .foregroundStyle(
                    value?.isEmpty == false
                        ? Color.primary
                        : Color(uiColor: .placeholderText)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dateRow(_ title: String, date: Date) -> some View {
        SearchFilterValueRow {
            HStack {
                Text(title)
                Spacer()
                Text(date.formatted(date: .numeric, time: .omitted))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch panel {
        case .time: return isCustomTimeFilter ? "自定义日期范围" : "时间"
        case .amount: return "金额"
        case .book: return "账本"
        case .account: return "账户"
        case .sort: return "排序"
        }
    }

    private var headerConfirmAction: (() -> Void)? {
        if panel == .amount || (panel == .time && isCustomTimeFilter) {
            return {}
        }
        return nil
    }

    private var confirmationTitle: String {
        !selectedAccountIDs.isEmpty
            ? "确定（\(selectedAccountIDs.count)）"
            : "确定"
    }

    private var customDates: (start: Date, end: Date) {
        if case let .custom(start, end) = timeRange { return (start, end) }
        let today = Calendar.current.startOfDay(for: .now)
        return (today, today)
    }

    private var accountGroups: [(AssetGroup, [Account])] {
        AssetGroup.allCases.compactMap { group in
            let members = accounts.filter { $0.type.assetGroup == group }
            return members.isEmpty ? nil : (group, members)
        }
    }
}

private struct SearchSummaryView: View {
    let result: BillSearchResult
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("共找到 \(result.totalCount) 条账单").font(.headline)
            HStack {
                summary("收入", value: result.income, color: incomeColor)
                Spacer()
                summary("支出", value: result.expense, color: HomePalette.expense)
            }
        }
        .padding(16)
        .ledgerContentSurface(cornerRadius: 22)
    }

    private func summary(_ title: String, value: BillSearchAmountAndCount, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.primary)
            HStack(spacing: 4) {
                Text(MoneyFormatter.string(value.amount, currencyCode: currencyCode)).foregroundStyle(color)
                Text("· \(value.count) 笔").foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private var incomeColor: Color {
        let convention = AmountColorConvention(rawValue: UserDefaults.standard.string(forKey: AppPreferences.amountColorKey) ?? "")
            ?? .regionalDefault(regionCode: Locale.current.region?.identifier)
        return AmountSemanticStyle.color(for: .income, convention: convention)
    }
}

private struct DynamicSummaryCard: View {
    let summary: BillSearchDynamicSummary
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(summary.category.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            Text(MoneyFormatter.string(summary.amount, currencyCode: currencyCode))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
            Text("\(summary.count) 笔").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 150, alignment: .leading)
        .ledgerContentSurface(cornerRadius: 20)
    }
}

private struct SearchResultRow: View {
    let transaction: LedgerTransaction
    let alwaysShowsDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HomeTransactionRow(transaction: transaction)
            if alwaysShowsDate {
                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        var point = CGPoint.zero
        var height: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x + size.width > width, point.x > 0 { point.x = 0; point.y += height + spacing; height = 0 }
            point.x += size.width + spacing
            height = max(height, size.height)
        }
        return CGSize(width: proposal.width ?? point.x, height: point.y + height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x + size.width > bounds.maxX, point.x > bounds.minX {
                point.x = bounds.minX; point.y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: point, proposal: ProposedViewSize(size))
            point.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct SearchTimeFilterView: View {
    let current: BillSearchTimeRange
    @Binding var showingCustom: Bool
    let cancel: () -> Void
    let apply: (BillSearchTimeRange) -> Void
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = Calendar.current.startOfDay(for: .now)

    var body: some View {
        VStack(spacing: 0) {
            SearchFilterCardHeader(
                title: showingCustom ? "自定义日期范围" : "时间",
                cancel: cancel,
                confirm: showingCustom ? { apply(.custom(start: start, end: end)) } : nil
            )
            Divider()
            if showingCustom {
                SearchFilterValueRow {
                    DatePicker("开始日期", selection: $start, displayedComponents: .date)
                }
                SearchFilterValueRow {
                    DatePicker("结束日期", selection: $end, in: start..., displayedComponents: .date)
                }
                Spacer(minLength: 0)
            } else {
                timeRow("全部时间", range: .all)
                timeRow("今天", range: .today)
                timeRow("本周", range: .thisWeek)
                timeRow("本月", range: .thisMonth)
                timeRow("本年", range: .thisYear)
                SearchFilterActionRow("自定义日期范围", trailingSymbol: "chevron.right") {
                    if case let .custom(oldStart, oldEnd) = current { start = oldStart; end = oldEnd }
                    showingCustom = true
                }
            }
        }
        .searchFilterInnerSurface()
    }

    private func timeRow(_ title: String, range: BillSearchTimeRange) -> some View {
        SearchFilterActionRow(title, isSelected: current == range) { apply(range) }
    }
}

private struct SearchAmountFilterView: View {
    let cancel: () -> Void
    let apply: (Decimal?, Decimal?) -> Void
    @State private var minimumText: String
    @State private var maximumText: String

    init(
        minimum: Decimal?,
        maximum: Decimal?,
        cancel: @escaping () -> Void,
        apply: @escaping (Decimal?, Decimal?) -> Void
    ) {
        self.cancel = cancel
        self.apply = apply
        _minimumText = State(initialValue: minimum.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _maximumText = State(initialValue: maximum.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchFilterCardHeader(title: "金额", cancel: cancel) {
                apply(DecimalParser.parse(minimumText), DecimalParser.parse(maximumText))
            }
            Divider()
            SearchFilterValueRow {
                TextField("最低金额", text: $minimumText).keyboardType(.decimalPad)
            }
            SearchFilterValueRow {
                TextField("最高金额", text: $maximumText).keyboardType(.decimalPad)
            }
            SearchFilterActionRow("清除金额", role: .destructive) {
                minimumText = ""
                maximumText = ""
            }
        }
        .searchFilterInnerSurface()
    }
}

private struct SearchBookFilterView: View {
    let books: [LedgerBook]
    let selectedID: UUID?
    let cancel: () -> Void
    let apply: (UUID?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchFilterCardHeader(title: "账本", cancel: cancel)
            Divider()
            bookRow("全部账本", id: nil)
            ForEach(books) { book in bookRow(book.name, id: book.id) }
        }
        .searchFilterInnerSurface()
    }

    private func bookRow(_ name: String, id: UUID?) -> some View {
        SearchFilterActionRow(name, isSelected: selectedID == id, usesRadio: true) { apply(id) }
    }
}

private struct SearchAccountFilterView: View {
    let accounts: [Account]
    let cancel: () -> Void
    let apply: (Set<UUID>) -> Void
    @State private var selectedIDs: Set<UUID>

    init(
        accounts: [Account],
        selectedIDs: Set<UUID>,
        cancel: @escaping () -> Void,
        apply: @escaping (Set<UUID>) -> Void
    ) {
        self.accounts = accounts
        self.cancel = cancel
        self.apply = apply
        _selectedIDs = State(initialValue: selectedIDs)
    }

    private var groups: [(AssetGroup, [Account])] {
        AssetGroup.allCases.compactMap { group in
            let members = accounts.filter { $0.type.assetGroup == group }
            return members.isEmpty ? nil : (group, members)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchFilterCardHeader(title: "账户", cancel: cancel)
            Divider()
            ScrollView(showsIndicators: accounts.count > 6) {
                LazyVStack(spacing: 0) {
                ForEach(groups, id: \.0.id) { group, members in
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .padding(.horizontal, 16)
                    ForEach(members) { account in
                        SearchFilterActionRow(
                            account.name,
                            isSelected: selectedIDs.contains(account.id),
                            usesRadio: true
                        ) { toggle(account.id) }
                    }
                }
            }
            }
            Divider()
            HStack {
                Button("清空选择") { selectedIDs.removeAll() }
                Spacer()
                Button(selectedIDs.isEmpty ? "确定" : "确定（\(selectedIDs.count)）") { apply(selectedIDs) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
        }
        .searchFilterInnerSurface()
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }
}

private struct SearchSortFilterView: View {
    let selected: BillSearchSortMode
    let cancel: () -> Void
    let apply: (BillSearchSortMode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchFilterCardHeader(title: "排序", cancel: cancel)
            Divider()
            ForEach(BillSearchSortMode.allCases) { mode in
                SearchFilterActionRow(mode.title, isSelected: mode == selected) { apply(mode) }
            }
        }
        .searchFilterInnerSurface()
    }
}

private struct SearchFilterCardHeader: View {
    let title: String
    let cancel: () -> Void
    let confirm: (() -> Void)?

    init(title: String, cancel: @escaping () -> Void, confirm: (() -> Void)? = nil) {
        self.title = title
        self.cancel = cancel
        self.confirm = confirm
    }

    var body: some View {
        ZStack {
            Text(title).font(.headline)
            HStack {
                Button("取消", action: cancel)
                Spacer()
                if let confirm { Button("确定", action: confirm).fontWeight(.semibold) }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}

private struct SearchFilterValueRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .frame(height: 50)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider().padding(.leading, 16) }
    }
}

private struct SearchFilterActionRow: View {
    let title: String
    var isSelected = false
    var usesRadio = false
    var trailingSymbol: String?
    var role: ButtonRole?
    let action: () -> Void

    init(
        _ title: String,
        isSelected: Bool = false,
        usesRadio: Bool = false,
        trailingSymbol: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.usesRadio = usesRadio
        self.trailingSymbol = trailingSymbol
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                Spacer()
                if let trailingSymbol {
                    Image(systemName: trailingSymbol).foregroundStyle(.tertiary)
                } else if usesRadio {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                } else if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? LedgerPalette.ink : Color.primary)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 16) }
    }
}

private extension View {
    func searchFilterInnerSurface() -> some View {
        background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct BillSearchCategoryView: View {
    @Environment(\.locale) private var locale
    let category: BillSearchDynamicCategory
    let transactions: [LedgerTransaction]
    let relations: [TransactionRelation]
    let settlements: [AASettlement]
    let summary: BillSearchDynamicSummary?
    private let service = BillSearchService()

    private var groups: [(Date, [LedgerTransaction])] {
        Dictionary(grouping: transactions) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value) }
            .sorted { $0.0 > $1.0 }
    }

    var body: some View {
        List {
            Section {
                Text("\(category.title)总额：\(MoneyFormatter.string(summary?.amount ?? 0, currencyCode: "CNY"))")
                Text("共 \(summary?.count ?? transactions.count) 笔")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.0) { date, items in
                Section(date.dayHeading(locale: locale)) {
                    ForEach(items) { transaction in
                        NavigationLink(value: transaction) {
                            VStack(alignment: .leading, spacing: 5) {
                                TransactionCompactRow(transaction: transaction)
                                if let categoryAmount = service.categoryAmount(
                                    transaction, category: category, relations: relations, settlements: settlements
                                ), categoryAmount != abs(transaction.sourceAmount ?? transaction.amount ?? 0) {
                                    Text("\(category.title)：\(MoneyFormatter.string(categoryAmount, currencyCode: transaction.currencyCode ?? "CNY"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(category.title)账单")
        .navigationBarTitleDisplayMode(.inline)
    }
}
