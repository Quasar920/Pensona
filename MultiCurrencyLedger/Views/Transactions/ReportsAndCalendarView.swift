import Charts
import SwiftData
import SwiftUI

struct ReportsView: View {
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \LedgerTransaction.date) private var transactions: [LedgerTransaction]
    @Query private var relations: [TransactionRelation]
    @Query private var aaSplits: [AASplit]
    @Query private var aaSettlements: [AASettlement]
    @Query private var rates: [ExchangeRate]

    @State private var metric: ReportMetric = .expense
    @State private var granularity: ReportGranularity = .daily
    @State private var dimension: ReportDimension = .category
    @State private var startDate = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var endDate = Date.now
    @State private var showingSettings = false
    @State private var showingBookSwitcher = false
    @State private var showingBookManagement = false
    @State private var showingTransactions = false
    @State private var showingCalendar = false

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var interval: DateInterval {
        let start = Calendar.current.startOfDay(for: min(startDate, endDate))
        let lastDay = Calendar.current.startOfDay(for: max(startDate, endDate))
        return DateInterval(
            start: start,
            end: Calendar.current.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        )
    }

    private var previousInterval: DateInterval {
        let dayCount = max(
            1,
            Calendar.current.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
        )
        let start = Calendar.current.date(
            byAdding: .day,
            value: -dayCount,
            to: interval.start
        ) ?? interval.start.addingTimeInterval(-interval.duration)
        return DateInterval(start: start, end: interval.start)
    }

    private var scopedTransactions: [LedgerTransaction] {
        guard let id = selectedBook?.id else { return [] }
        return transactions.filter {
            $0.sourceAccount?.book?.id == id || $0.destinationAccount?.book?.id == id
        }
    }

    private var service: ReportQueryService {
        ReportQueryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
    }

    private var trend: ReportResult {
        service.trend(
            transactions: scopedTransactions,
            relations: relations,
            interval: interval,
            metric: metric,
            granularity: granularity,
            aaSplits: aaSplits,
            aaSettlements: aaSettlements
        )
    }

    private var breakdown: ReportResult {
        service.breakdown(
            transactions: scopedTransactions,
            relations: relations,
            interval: interval,
            metric: metric,
            dimension: dimension,
            aaSplits: aaSplits,
            aaSettlements: aaSettlements
        )
    }

    private var previousTrend: ReportResult {
        service.trend(
            transactions: scopedTransactions,
            relations: relations,
            interval: previousInterval,
            metric: metric,
            granularity: granularity,
            aaSplits: aaSplits,
            aaSettlements: aaSettlements
        )
    }

    private func comparisonRate(difference: Decimal, previousTotal: Decimal) -> Double? {
        let previousMagnitude = absDecimal(previousTotal)
        guard previousMagnitude != 0 else { return nil }
        return NSDecimalNumber(decimal: difference / previousMagnitude).doubleValue
    }

    private var metricColor: Color {
        switch metric {
        case .expense: ReportPalette.expense
        case .income: ReportPalette.income
        case .net: HomePalette.accent
        }
    }

    private func compositionSlices(for result: ReportResult) -> [ReportSlice] {
        let buckets = result.buckets
            .filter { absDouble($0.value) > 0 }
            .sorted { absDouble($0.value) > absDouble($1.value) }
        let visibleCount = buckets.count > 6 ? 5 : buckets.count
        var slices = buckets.prefix(visibleCount).enumerated().map { index, bucket in
            ReportSlice(
                id: bucket.id,
                title: bucket.title,
                value: bucket.value,
                magnitude: absDouble(bucket.value),
                color: ReportPalette.sectorColors[index % ReportPalette.sectorColors.count]
            )
        }

        let remaining = buckets.dropFirst(visibleCount)
        if !remaining.isEmpty {
            slices.append(
                ReportSlice(
                    id: "other",
                    title: "其他 \(remaining.count) 项",
                    value: remaining.reduce(Decimal.zero) { $0 + $1.value },
                    magnitude: remaining.reduce(0) { $0 + absDouble($1.value) },
                    color: ReportPalette.sectorColors[visibleCount % ReportPalette.sectorColors.count]
                )
            )
        }
        return slices
    }

    var body: some View {
        let currentTrend = trend
        let currentBreakdown = breakdown
        let earlierTrend = previousTrend
        let difference = currentTrend.total - earlierTrend.total
        let rate = comparisonRate(difference: difference, previousTotal: earlierTrend.total)
        let slices = compositionSlices(for: currentBreakdown)
        let missingCodes = currentTrend.missingCodes
            .union(currentBreakdown.missingCodes)
            .union(earlierTrend.missingCodes)

        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ReportSummaryCard(
                            metric: metric,
                            total: currentTrend.total,
                            previousTotal: earlierTrend.total,
                            difference: difference,
                            comparisonRate: rate,
                            previousRangeTitle: dateRangeTitle(previousInterval),
                            currencyCode: baseCurrencyCode,
                            accent: metricColor
                        )

                        ReportFilterCard(
                            metric: $metric,
                            startDate: $startDate,
                            endDate: $endDate,
                            granularity: $granularity,
                            dimension: $dimension
                        )

                        ReportTrendCard(
                            result: currentTrend,
                            metric: metric,
                            granularity: granularity,
                            currencyCode: baseCurrencyCode,
                            accent: metricColor
                        )

                        ReportCompositionCard(
                            total: currentTrend.total,
                            slices: slices,
                            metric: metric,
                            dimension: dimension,
                            currencyCode: baseCurrencyCode
                        )

                        if !missingCodes.isEmpty {
                            ReportRateWarningCard(codes: missingCodes)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, RootEntryLayout.scrollContentClearance)
                }
            }
            .navigationTitle("报表")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingBookSwitcher = true } label: {
                        Label(selectedBook?.name ?? "选择账本", systemImage: "book.closed")
                    }
                    .accessibilityHint("切换账本")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingCalendar = true } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("账单日历")

                    Menu {
                        Button { showingTransactions = true } label: {
                            Label("搜索流水", systemImage: "magnifyingglass")
                        }
                        Button { showingBookManagement = true } label: {
                            Label("管理账本", systemImage: "slider.horizontal.3")
                        }
                        Divider()
                        Button { showingSettings = true } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多报表操作")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingBookSwitcher) {
                LedgerBookSwitcherView(selectedBookID: $selectedBookID)
            }
            .sheet(isPresented: $showingBookManagement) { LedgerBookManagementView() }
            .sheet(isPresented: $showingTransactions) { TransactionListView() }
            .sheet(isPresented: $showingCalendar) { TransactionCalendarView() }
            .onAppear(perform: ensureSelectedBook)
            .onChange(of: books.count) { _, _ in ensureSelectedBook() }
        }
    }

    private func ensureSelectedBook() {
        guard let first = books.first else { return }
        if !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
    }

    private func dateRangeTitle(_ value: DateInterval) -> String {
        let finalDay = Calendar.current.date(byAdding: .day, value: -1, to: value.end) ?? value.end
        let calendar = Calendar.current
        let start = calendar.dateComponents([.year, .month, .day], from: value.start)
        let end = calendar.dateComponents([.year, .month, .day], from: finalDay)
        guard let startYear = start.year, let startMonth = start.month, let startDay = start.day,
              let endYear = end.year, let endMonth = end.month, let endDay = end.day else { return "" }
        if startYear == endYear {
            return "\(startYear)/\(startMonth)/\(startDay) - \(endMonth)/\(endDay)"
        }
        return "\(startYear)/\(startMonth)/\(startDay) - \(endYear)/\(endMonth)/\(endDay)"
    }

    private func absDecimal(_ value: Decimal) -> Decimal { value < 0 ? -value : value }

    private func absDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: absDecimal(value)).doubleValue
    }
}

private struct ReportFilterCard: View {
    @Binding var metric: ReportMetric
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var granularity: ReportGranularity
    @Binding var dimension: ReportDimension

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            filterTitle("统计指标", systemImage: "scope")
            Picker("统计指标", selection: $metric) {
                ForEach(ReportMetric.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Divider().opacity(0.5)

            filterTitle("日期范围", systemImage: "calendar")
            HStack(spacing: 7) {
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReportPalette.secondaryInk)
                DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().opacity(0.5)

            filterTitle("趋势粒度", systemImage: "chart.bar.fill")
            Picker("趋势粒度", selection: $granularity) {
                ForEach(ReportGranularity.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            filterTitle("构成维度", systemImage: "chart.pie.fill")
            Picker("构成维度", selection: $dimension) {
                ForEach(ReportDimension.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(18)
        .ledgerGlassCard(cornerRadius: 26, tint: HomePalette.accent)
    }

    private func filterTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ReportPalette.secondaryInk)
    }
}

private struct ReportSummaryCard: View {
    let metric: ReportMetric
    let total: Decimal
    let previousTotal: Decimal
    let difference: Decimal
    let comparisonRate: Double?
    let previousRangeTitle: String
    let currencyCode: String
    let accent: Color

    private var differenceText: String {
        let amount = MoneyFormatter.string(absDecimal(difference), currencyCode: currencyCode)
        if difference > 0 { return "+\(amount)" }
        if difference < 0 { return "−\(amount)" }
        return MoneyFormatter.string(0, currencyCode: currencyCode)
    }

    private var rateText: String? {
        comparisonRate.map {
            $0.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
        }
    }

    private var comparisonColor: Color {
        guard difference != 0 else { return ReportPalette.secondaryInk }
        let isFavorable = metric == .expense ? difference < 0 : difference > 0
        return isFavorable ? ReportPalette.income : ReportPalette.expense
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("\(metric.title)总额", systemImage: metric.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Spacer()
                Text(currencyCode)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ReportPalette.secondaryInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }

            Text(MoneyFormatter.string(total, currencyCode: currencyCode))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(ReportPalette.ink)
                .monospacedDigit()
                .minimumScaleFactor(0.66)
                .lineLimit(1)

            VStack(spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("上一等长周期")
                            .font(.subheadline.weight(.semibold))
                        Text(previousRangeTitle)
                            .font(.caption2)
                            .foregroundStyle(ReportPalette.secondaryInk)
                    }
                    Spacer()
                    Text(MoneyFormatter.string(previousTotal, currencyCode: currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }

                HStack {
                    Text("差额")
                        .font(.caption)
                        .foregroundStyle(ReportPalette.secondaryInk)
                    Spacer()
                    Text([differenceText, rateText].compactMap { $0 }.joined(separator: "  "))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(comparisonColor)
                        .monospacedDigit()
                }
            }
            .padding(13)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .padding(20)
        .ledgerGlassCard(cornerRadius: 28, tint: accent)
    }

    private func absDecimal(_ value: Decimal) -> Decimal { value < 0 ? -value : value }
}

private struct ReportTrendCard: View {
    let result: ReportResult
    let metric: ReportMetric
    let granularity: ReportGranularity
    let currencyCode: String
    let accent: Color

    private var points: [ReportTrendPoint] {
        result.buckets.compactMap { bucket in
            guard let timestamp = Double(bucket.id) else { return nil }
            return ReportTrendPoint(
                id: bucket.id,
                date: Date(timeIntervalSinceReferenceDate: timestamp),
                title: bucket.title,
                amount: bucket.value,
                value: NSDecimalNumber(decimal: bucket.value).doubleValue
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var visiblePointCount: Int {
        switch granularity {
        case .daily: 14
        case .weekly: 12
        case .monthly: 12
        case .yearly: 6
        }
    }

    private var visibleDomain: TimeInterval {
        let day: TimeInterval = 86_400
        switch granularity {
        case .daily: return day * 14
        case .weekly: return day * 7 * 12
        case .monthly: return day * 31 * 12
        case .yearly: return day * 366 * 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReportSectionHeader(
                title: "\(metric.title)趋势",
                subtitle: "按\(granularity.title)汇总 · \(points.count) 个周期",
                systemImage: "chart.bar.fill",
                accent: accent
            )

            if points.isEmpty {
                ReportEmptyState(
                    title: "当前范围没有趋势数据",
                    message: "调整日期或统计指标后再看看",
                    systemImage: "chart.bar.xaxis"
                )
                .frame(height: 190)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("周期", point.date),
                        y: .value("金额", point.value)
                    )
                    .foregroundStyle(point.value < 0 ? ReportPalette.negativeBar : accent)
                    .cornerRadius(5)
                    .accessibilityLabel(point.title)
                    .accessibilityValue(MoneyFormatter.string(point.amount, currencyCode: currencyCode))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisTitle(for: date))
                            }
                        }
                            .foregroundStyle(ReportPalette.secondaryInk)
                        AxisTick().foregroundStyle(Color.clear)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4]))
                            .foregroundStyle(ReportPalette.grid)
                        AxisValueLabel()
                            .foregroundStyle(ReportPalette.secondaryInk)
                    }
                }
                .chartScrollableAxes(points.count > visiblePointCount ? .horizontal : [])
                .chartXVisibleDomain(length: points.count > visiblePointCount ? visibleDomain : fullDomain)
                .frame(height: 220)
            }
        }
        .padding(18)
        .ledgerGlassCard(cornerRadius: 28, tint: accent)
    }

    private var fullDomain: TimeInterval {
        guard let first = points.first?.date, let last = points.last?.date else { return visibleDomain }
        return max(visibleDomain / Double(visiblePointCount), last.timeIntervalSince(first) + 1)
    }

    private func axisTitle(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        switch granularity {
        case .daily, .weekly:
            return "\(month)/\(day)"
        case .monthly:
            return "\(year)/\(month)"
        case .yearly:
            return "\(year)"
        }
    }
}

private struct ReportCompositionCard: View {
    let total: Decimal
    let slices: [ReportSlice]
    let metric: ReportMetric
    let dimension: ReportDimension
    let currencyCode: String

    private var magnitudeTotal: Double {
        slices.reduce(0) { $0 + $1.magnitude }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReportSectionHeader(
                title: "\(metric.title)构成",
                subtitle: "按\(dimension.title)分类",
                systemImage: "chart.pie.fill",
                accent: ReportPalette.violet
            )

            if slices.isEmpty {
                ReportEmptyState(
                    title: "当前范围没有构成数据",
                    message: "记账后会在这里显示\(dimension.title)分布",
                    systemImage: "chart.pie"
                )
                .frame(height: 190)
            } else {
                ZStack {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("金额绝对值", slice.magnitude),
                            innerRadius: .ratio(0.64),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(slice.color)
                        .accessibilityLabel(slice.title)
                        .accessibilityValue(MoneyFormatter.string(slice.value, currencyCode: currencyCode))
                    }
                    .chartLegend(.hidden)

                    VStack(spacing: 3) {
                        Text("\(metric.title)总额")
                            .font(.caption2)
                            .foregroundStyle(ReportPalette.secondaryInk)
                        Text(MoneyFormatter.compactString(total, currencyCode: currencyCode))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(ReportPalette.ink)
                            .monospacedDigit()
                    }
                }
                .frame(height: 220)

                VStack(spacing: 12) {
                    ForEach(slices) { slice in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(slice.color)
                                .frame(width: 9, height: 9)
                            Text(slice.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if magnitudeTotal > 0 {
                                Text(slice.magnitude / magnitudeTotal, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption)
                                    .foregroundStyle(ReportPalette.secondaryInk)
                                    .monospacedDigit()
                            }
                            Text(MoneyFormatter.string(slice.value, currencyCode: currencyCode))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(slice.value < 0 ? ReportPalette.negativeBar : ReportPalette.ink)
                                .monospacedDigit()
                        }
                    }
                }

                Text(compositionNote)
                    .font(.caption2)
                    .foregroundStyle(ReportPalette.secondaryInk)
            }
        }
        .padding(18)
        .ledgerGlassCard(cornerRadius: 28, tint: ReportPalette.violet)
    }

    private var compositionNote: String {
        return "扇区按金额绝对值绘制，明细金额保留正负号。"
    }
}

private struct ReportSectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(ReportPalette.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ReportPalette.secondaryInk)
            }
            Spacer()
        }
    }
}

private struct ReportEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(HomePalette.accent.opacity(0.72))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ReportPalette.ink)
            Text(message)
                .font(.caption)
                .foregroundStyle(ReportPalette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ReportRateWarningCard: View {
    let codes: Set<String>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(ReportPalette.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("汇率数据不完整")
                    .font(.subheadline.weight(.semibold))
                Text("缺少 \(codes.sorted().joined(separator: "、")) 汇率，相关金额未计入当前周期或上一等长周期。")
                    .font(.caption)
                    .foregroundStyle(ReportPalette.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .ledgerGlassCard(cornerRadius: 22, tint: ReportPalette.warning)
    }
}

private struct ReportTrendPoint: Identifiable {
    let id: String
    let date: Date
    let title: String
    let amount: Decimal
    let value: Double
}

private struct ReportSlice: Identifiable {
    let id: String
    let title: String
    let value: Decimal
    let magnitude: Double
    let color: Color
}

private enum ReportPalette {
    // 文字墨色使用语义色，保证深色模式与增强对比度下可读（交接文档 §10.2）
    static let ink = Color.primary
    static let secondaryInk = Color.secondary
    static let expense = Color(red: 218 / 255, green: 82 / 255, blue: 91 / 255)
    static let income = Color(red: 35 / 255, green: 157 / 255, blue: 112 / 255)
    static let negativeBar = Color(red: 232 / 255, green: 118 / 255, blue: 104 / 255)
    static let violet = Color(red: 111 / 255, green: 92 / 255, blue: 205 / 255)
    static let warning = Color(red: 222 / 255, green: 133 / 255, blue: 42 / 255)
    static let grid = Color(red: 111 / 255, green: 118 / 255, blue: 132 / 255).opacity(0.2)
    static let sectorColors: [Color] = [
        HomePalette.accent,
        Color(red: 111 / 255, green: 92 / 255, blue: 205 / 255),
        Color(red: 35 / 255, green: 157 / 255, blue: 112 / 255),
        Color(red: 232 / 255, green: 118 / 255, blue: 104 / 255),
        Color(red: 237 / 255, green: 170 / 255, blue: 67 / 255),
        Color(red: 57 / 255, green: 171 / 255, blue: 190 / 255),
        Color(red: 208 / 255, green: 91 / 255, blue: 149 / 255),
        Color(red: 109 / 255, green: 126 / 255, blue: 151 / 255)
    ]
}

private extension ReportMetric {
    var symbolName: String {
        switch self {
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case .net: "equal"
        }
    }
}

struct TransactionCalendarView: View {
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query private var books: [LedgerBook]
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private var scoped: [LedgerTransaction] {
        guard let id = UUID(uuidString: selectedBookID) ?? books.first?.id else { return [] }
        return transactions.filter {
            $0.sourceAccount?.book?.id == id || $0.destinationAccount?.book?.id == id
        }
    }

    private var days: [Date?] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month),
              let range = Calendar.current.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = Calendar.current.component(.weekday, from: interval.start)
        let prefix = Array<Date?>(repeating: nil, count: weekday - 1)
        return prefix + range.compactMap { day in
            Calendar.current.date(byAdding: .day, value: day - 1, to: interval.start)
        }.map(Optional.some)
    }

    private var selectedTransactions: [LedgerTransaction] {
        scoped.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(month.formatted(.dateTime.year().month())).font(.headline)
                        Spacer()
                        Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                    }
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) {
                            Text($0).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                            if let day { dayCell(day) } else { Color.clear.frame(height: 40) }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section(selectedDay.formatted(date: .long, time: .omitted)) {
                    if selectedTransactions.isEmpty {
                        Text("当天没有交易").foregroundStyle(.secondary)
                    } else {
                        ForEach(selectedTransactions) { transaction in
                            NavigationLink(value: transaction) { TransactionCompactRow(transaction: transaction) }
                        }
                    }
                }
            }
            .navigationTitle("账单日历")
            .navigationDestination(for: LedgerTransaction.self) { TransactionDetailView(transaction: $0) }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let hasTransactions = scoped.contains { Calendar.current.isDate($0.date, inSameDayAs: day) }
        let selected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.subheadline.weight(selected ? .bold : .regular))
                Circle().fill(hasTransactions ? Color.accentColor : Color.clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month
        selectedDay = month
    }
}
