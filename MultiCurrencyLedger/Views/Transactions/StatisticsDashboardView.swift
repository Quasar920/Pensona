import Charts
import SwiftData
import SwiftUI

struct ReportsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]

    @State private var state = StatisticsPageState()
    @State private var snapshot: StatisticsDashboardSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedBucketKey: String?
    @State private var showingBookSwitcher = false
    @State private var cacheRevision = 0

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var interval: DateInterval { state.interval() }

    private var reloadKey: StatisticsReloadKey {
        StatisticsReloadKey(
            bookID: selectedBook?.id,
            section: state.section,
            start: interval.start,
            end: interval.end,
            baseCurrencyCode: baseCurrencyCode,
            cacheRevision: cacheRevision
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        StatisticsSectionPicker(selection: $state.section)
                        StatisticsRangePicker(state: $state)
                        dashboardContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, RootEntryLayout.scrollContentClearance)
                }
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingBookSwitcher = true } label: {
                        Label(selectedBook?.name ?? AppLocalization.string("选择账本"), systemImage: "book.closed")
                    }
                    .accessibilityHint("切换统计账本")
                }
            }
            .sheet(isPresented: $showingBookSwitcher) {
                LedgerBookSwitcherView(selectedBookID: $selectedBookID)
            }
            .onAppear(perform: ensureSelectedBook)
            .onChange(of: books.count) { _, _ in ensureSelectedBook() }
            .onChange(of: selectedBucketKey) { oldValue, newValue in
                guard let newValue, oldValue != newValue else { return }
                HapticFeedbackService().selection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ledgerTransactionsDidChange)) { _ in
                Task {
                    await StatisticsDashboardService(context: context).invalidateCache()
                    cacheRevision += 1
                }
            }
            .task(id: reloadKey) {
                await load(reloadKey)
            }
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        if isLoading && snapshot == nil {
            ProgressView("正在统计…")
                .frame(maxWidth: .infinity, minHeight: 300)
                .ledgerGlassCard(cornerRadius: 28, tint: HomePalette.accent)
        } else if let snapshot {
            StatisticsChartPanel(
                snapshot: snapshot,
                currencyCode: baseCurrencyCode,
                selectedBucketKey: $selectedBucketKey
            )
            if !snapshot.missingCodes.isEmpty {
                Label(
                    "缺少 \(snapshot.missingCodes.sorted().joined(separator: "、")) 汇率，相关金额未计入。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .ledgerGlassCard(cornerRadius: 20, tint: .orange)
            }
        } else {
            ContentUnavailableView(
                "暂无统计结果",
                systemImage: "chart.bar.xaxis",
                description: Text(errorMessage ?? AppLocalization.string("请选择账本后重试"))
            )
            .frame(maxWidth: .infinity, minHeight: 300)
            .ledgerGlassCard(cornerRadius: 28, tint: HomePalette.accent)
        }
    }

    private func load(_ key: StatisticsReloadKey) async {
        guard let bookID = key.bookID else {
            snapshot = nil
            return
        }
        isLoading = true
        errorMessage = nil
        selectedBucketKey = nil
        do {
            let result = try await StatisticsDashboardService(context: context).load(
                bookID: bookID,
                section: key.section,
                interval: DateInterval(start: key.start, end: key.end),
                baseCurrencyCode: key.baseCurrencyCode
            )
            try Task.checkCancellation()
            guard reloadKey == key else { return }
            snapshot = result
        } catch is CancellationError {
            return
        } catch {
            guard reloadKey == key else { return }
            snapshot = nil
            errorMessage = error.localizedDescription
        }
        if reloadKey == key { isLoading = false }
    }

    private func ensureSelectedBook() {
        guard let first = books.first else { return }
        if !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
    }
}

private struct StatisticsReloadKey: Hashable {
    let bookID: UUID?
    let section: StatisticsSection
    let start: Date
    let end: Date
    let baseCurrencyCode: String
    let cacheRevision: Int
}

private struct StatisticsSectionPicker: View {
    @Binding var selection: StatisticsSection

    var body: some View {
        Picker("统计页面", selection: $selection) {
            ForEach(StatisticsSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(8)
        .ledgerGlassCard(cornerRadius: 20, tint: HomePalette.accent)
        .accessibilityLabel("统计内容")
    }
}

private struct StatisticsRangePicker: View {
    @Binding var state: StatisticsPageState

    private var interval: DateInterval { state.interval() }

    var body: some View {
        VStack(spacing: 13) {
            Picker("统计范围", selection: $state.range) {
                ForEach(StatisticsRangePreset.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            if state.range == .custom {
                HStack(spacing: 8) {
                    DatePicker("开始", selection: $state.customStart, displayedComponents: .date)
                        .labelsHidden()
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    DatePicker("结束", selection: $state.customEnd, displayedComponents: .date)
                        .labelsHidden()
                }
            } else {
                HStack {
                    Button { state.moveRange(by: -1) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("statistics-range-previous")
                    Spacer()
                    Text(rangeTitle)
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("当前日期范围 \(rangeTitle)")
                    Spacer()
                    Button { state.moveRange(by: 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("statistics-range-next")
                }
            }
        }
        .padding(14)
        .ledgerGlassCard(cornerRadius: 24, tint: HomePalette.accent)
    }

    private var rangeTitle: String {
        let finalDay = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(finalDay.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct StatisticsChartPanel: View {
    let snapshot: StatisticsDashboardSnapshot
    let currencyCode: String
    @Binding var selectedBucketKey: String?

    private var selectedBucket: StatisticsDashboardBucket? {
        snapshot.buckets.first { $0.key == selectedBucketKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(panelTitle).font(.title3.bold())
                Text(panelSubtitle).font(.caption).foregroundStyle(.secondary)
            }

            if snapshot.buckets.isEmpty {
                ContentUnavailableView("当前范围没有数据", systemImage: "chart.bar.xaxis")
                    .frame(maxWidth: .infinity, minHeight: 230)
            } else {
                Chart(snapshot.buckets) { bucket in
                    BarMark(
                        x: .value("节点", bucket.title),
                        y: .value("金额", NSDecimalNumber(decimal: bucket.value).doubleValue)
                    )
                    .foregroundStyle(bucket.value < 0 ? Color.orange : HomePalette.accent)
                    .cornerRadius(6)
                    .opacity(selectedBucketKey == nil || selectedBucketKey == bucket.key ? 1 : 0.42)
                    .accessibilityLabel(bucket.title)
                    .accessibilityValue(MoneyFormatter.string(bucket.value, currencyCode: currencyCode))

                    if selectedBucketKey == bucket.key {
                        RuleMark(x: .value("选中节点", bucket.title))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .annotation(position: .top) {
                                Text(MoneyFormatter.compactString(bucket.value, currencyCode: currencyCode))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 9)
                                    .frame(minHeight: 30)
                                    .background(.regularMaterial, in: Capsule())
                            }
                    }
                }
                .chartXSelection(value: bucketTitleSelection)
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                        AxisValueLabel()
                    }
                }
                .chartScrollableAxes(snapshot.buckets.count > 8 ? .horizontal : [])
                .chartXVisibleDomain(length: snapshot.buckets.count > 8 ? 8 : max(snapshot.buckets.count, 1))
                .frame(height: 280)
                .accessibilityLabel(panelTitle)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("收入")
                    Spacer()
                    Text(MoneyFormatter.string(snapshot.income, currencyCode: currencyCode)).monospacedDigit()
                }
                HStack {
                    Text("支出")
                    Spacer()
                    Text(MoneyFormatter.string(snapshot.expense, currencyCode: currencyCode)).monospacedDigit()
                }
                Divider()
                Text(accessibleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("图表摘要：\(accessibleSummary)")
            }
            .font(.subheadline)
        }
        .padding(20)
        .ledgerGlassCard(cornerRadius: 30, tint: HomePalette.accent)
    }

    private var bucketTitleSelection: Binding<String?> {
        Binding(
            get: { selectedBucket?.title },
            set: { title in selectedBucketKey = snapshot.buckets.first(where: { $0.title == title })?.key }
        )
    }

    private var panelTitle: String {
        switch snapshot.section {
        case .overview: AppLocalization.string( "收支概览")
        case .categories: AppLocalization.string( "支出分类")
        case .assets: AppLocalization.string( "账户净变动")
        case .calendar: AppLocalization.string( "日历净额")
        }
    }

    private var panelSubtitle: String {
        AppLocalization.string( "\(snapshot.transactionCount) 笔交易 · 拖动图表查看节点")
    }

    private var accessibleSummary: String {
        let bucketText = snapshot.buckets.prefix(6).map {
            "\($0.title) \(MoneyFormatter.string($0.value, currencyCode: currencyCode))"
        }.joined(separator: "；")
        return bucketText.isEmpty ? AppLocalization.string( "当前范围没有可展示节点。") : bucketText
    }
}
