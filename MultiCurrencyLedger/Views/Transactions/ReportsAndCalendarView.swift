import SwiftData
import SwiftUI

struct ReportsView: View {
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query private var books: [LedgerBook]
    @Query(sort: \LedgerTransaction.date) private var transactions: [LedgerTransaction]
    @Query private var relations: [TransactionRelation]
    @Query private var rates: [ExchangeRate]
    @State private var metric: ReportMetric = .expense
    @State private var granularity: ReportGranularity = .daily
    @State private var dimension: ReportDimension = .category
    @State private var startDate = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var endDate = Date.now

    private var interval: DateInterval {
        let start = Calendar.current.startOfDay(for: min(startDate, endDate))
        let lastDay = Calendar.current.startOfDay(for: max(startDate, endDate))
        return DateInterval(
            start: start,
            end: Calendar.current.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        )
    }

    private var scopedTransactions: [LedgerTransaction] {
        guard let id = UUID(uuidString: selectedBookID) ?? books.first?.id else { return [] }
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
            granularity: granularity
        )
    }

    private var breakdown: ReportResult {
        service.breakdown(
            transactions: scopedTransactions,
            relations: relations,
            interval: interval,
            metric: metric,
            dimension: dimension
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("范围") {
                    Picker("指标", selection: $metric) {
                        ForEach(ReportMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束", selection: $endDate, displayedComponents: .date)
                }
                Section("趋势") {
                    Picker("粒度", selection: $granularity) {
                        ForEach(ReportGranularity.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    reportRows(trend)
                }
                Section("构成") {
                    Picker("维度", selection: $dimension) {
                        ForEach(ReportDimension.allCases) { Text($0.title).tag($0) }
                    }
                    reportRows(breakdown)
                }
                if !trend.missingCodes.isEmpty || !breakdown.missingCodes.isEmpty {
                    Section {
                        Text("缺少 \(trend.missingCodes.union(breakdown.missingCodes).sorted().joined(separator: "、")) 汇率，相关金额未计入。")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("统计报表")
        }
    }

    @ViewBuilder
    private func reportRows(_ result: ReportResult) -> some View {
        if result.buckets.isEmpty {
            Text("当前范围没有数据").foregroundStyle(.secondary)
        } else {
            ForEach(result.buckets) { bucket in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(bucket.title)
                        Spacer()
                        Text(MoneyFormatter.plain(bucket.value, currencyCode: baseCurrencyCode))
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        Capsule().fill(Color.accentColor.opacity(0.15))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor)
                                    .frame(width: proxy.size.width * ratio(bucket.value, total: result.buckets))
                            }
                    }
                    .frame(height: 5)
                }
            }
        }
    }

    private func ratio(_ value: Decimal, total: [ReportBucket]) -> Double {
        let maximum = total.map { absNumber($0.value) }.max() ?? 0
        guard maximum > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: absNumber(value) / maximum).doubleValue)
    }

    private func absNumber(_ value: Decimal) -> Decimal { value < 0 ? -value : value }
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
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month
        selectedDay = month
    }
}
