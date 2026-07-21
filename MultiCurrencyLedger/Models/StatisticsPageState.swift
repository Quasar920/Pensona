import Foundation

enum StatisticsSection: String, CaseIterable, Identifiable, Sendable {
    case overview, categories, assets, calendar

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: AppLocalization.string( "概览")
        case .categories: AppLocalization.string( "分类")
        case .assets: AppLocalization.string( "资产")
        case .calendar: AppLocalization.string( "日历")
        }
    }
}

enum StatisticsRangePreset: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: AppLocalization.string( "周")
        case .month: AppLocalization.string( "月")
        case .year: AppLocalization.string( "年")
        case .custom: AppLocalization.string( "自定义")
        }
    }
}

struct StatisticsPageState: Equatable, Sendable {
    var section: StatisticsSection = .overview
    var range: StatisticsRangePreset = .month
    var anchorDate: Date
    var customStart: Date
    var customEnd: Date

    init(now: Date = .now, calendar: Calendar = .current) {
        anchorDate = now
        customStart = calendar.date(byAdding: .day, value: -29, to: now) ?? now
        customEnd = now
    }

    func interval(calendar: Calendar = .current) -> DateInterval {
        switch range {
        case .week:
            calendar.dateInterval(of: .weekOfYear, for: anchorDate)
                ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 86_400 * 7)
        case .month:
            calendar.dateInterval(of: .month, for: anchorDate)
                ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 0)
        case .year:
            calendar.dateInterval(of: .year, for: anchorDate)
                ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 0)
        case .custom:
            customInterval(calendar: calendar)
        }
    }

    mutating func moveRange(by offset: Int, calendar: Calendar = .current) {
        guard range != .custom else { return }
        let component: Calendar.Component = switch range {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .custom: .day
        }
        anchorDate = calendar.date(byAdding: component, value: offset, to: anchorDate) ?? anchorDate
    }

    private func customInterval(calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: min(customStart, customEnd))
        let finalDay = calendar.startOfDay(for: max(customStart, customEnd))
        let end = calendar.date(byAdding: .day, value: 1, to: finalDay) ?? finalDay
        return DateInterval(start: start, end: end)
    }
}
