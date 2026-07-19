import Foundation
import SwiftData

enum RecurringScheduleError: LocalizedError, Equatable {
    case emptyName
    case invalidInterval
    case invalidDateRange
    case invalidTimeZone
    case generationLimitReached

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入周期账单名称"
        case .invalidInterval: "周期必须大于 0"
        case .invalidDateRange: "结束日期不能早于开始日期"
        case .invalidTimeZone: "周期账单的时区无效"
        case .generationLimitReached: "一次最多补生成 500 笔，请缩小日期范围后重试"
        }
    }
}

struct RecurrenceDateCalculator {
    static func next(
        after current: Date,
        frequency: RecurringFrequency,
        interval: Int,
        anchorDate: Date,
        calendar inputCalendar: Calendar
    ) -> Date? {
        guard interval > 0 else { return nil }
        var calendar = inputCalendar
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: current)
        case .weekly:
            return calendar.date(byAdding: .day, value: interval * 7, to: current)
        case .monthly:
            return dateByAdvancingMonth(
                current: current,
                anchorDate: anchorDate,
                value: interval,
                calendar: &calendar
            )
        case .yearly:
            return dateByAdvancingYear(
                current: current,
                anchorDate: anchorDate,
                value: interval,
                calendar: &calendar
            )
        }
    }

    private static func dateByAdvancingMonth(
        current: Date,
        anchorDate: Date,
        value: Int,
        calendar: inout Calendar
    ) -> Date? {
        let currentParts = calendar.dateComponents([.year, .month], from: current)
        guard let monthStart = calendar.date(from: DateComponents(
            year: currentParts.year, month: currentParts.month, day: 1
        )),
        let targetMonth = calendar.date(byAdding: .month, value: value, to: monthStart) else {
            return nil
        }
        let targetParts = calendar.dateComponents([.year, .month], from: targetMonth)
        let anchorParts = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: anchorDate)
        let dayCount = calendar.range(of: .day, in: .month, for: targetMonth)?.count ?? 28
        return calendar.date(from: DateComponents(
            year: targetParts.year,
            month: targetParts.month,
            day: min(anchorParts.day ?? 1, dayCount),
            hour: anchorParts.hour,
            minute: anchorParts.minute,
            second: anchorParts.second,
            nanosecond: anchorParts.nanosecond
        ))
    }

    private static func dateByAdvancingYear(
        current: Date,
        anchorDate: Date,
        value: Int,
        calendar: inout Calendar
    ) -> Date? {
        let currentYear = calendar.component(.year, from: current)
        let anchor = calendar.dateComponents([.month, .day, .hour, .minute, .second, .nanosecond], from: anchorDate)
        let targetYear = currentYear + value
        let month = anchor.month ?? 1
        guard let monthStart = calendar.date(from: DateComponents(
            year: targetYear, month: month, day: 1
        )) else { return nil }
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        return calendar.date(from: DateComponents(
            year: targetYear,
            month: month,
            day: min(anchor.day ?? 1, dayCount),
            hour: anchor.hour,
            minute: anchor.minute,
            second: anchor.second,
            nanosecond: anchor.nanosecond
        ))
    }
}

@MainActor
final class RecurringScheduleService {
    private let context: ModelContext
    private let codec = AutomationDraftCodec()

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func create(
        name: String,
        draft: TransactionDraft,
        frequency: RecurringFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> RecurringSchedule {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RecurringScheduleError.emptyName }
        guard interval > 0 else { throw RecurringScheduleError.invalidInterval }
        guard endDate.map({ $0 >= startDate }) ?? true else {
            throw RecurringScheduleError.invalidDateRange
        }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw RecurringScheduleError.invalidTimeZone
        }
        _ = try TransactionImpactCalculator().deltas(for: draft)
        let encoded = try codec.encode(draft)
        let schedule = RecurringSchedule(
            name: cleanName,
            bookID: encoded.bookID,
            frequency: frequency,
            interval: interval,
            anchorDate: startDate,
            endDate: endDate,
            timeZoneIdentifier: timeZoneIdentifier,
            draftData: encoded.data
        )
        context.insert(schedule)
        try context.save()
        return schedule
    }

    @discardableResult
    func generateDue(
        for schedule: RecurringSchedule,
        through date: Date = .now
    ) throws -> [LedgerTransaction] {
        guard !schedule.isPaused, !schedule.isArchived else { return [] }
        guard let timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) else {
            throw RecurringScheduleError.invalidTimeZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let wallets = try context.fetch(FetchDescriptor<CurrencyWallet>())
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let existingKeys = Set(try context.fetch(FetchDescriptor<RecurringOccurrence>())
            .filter { $0.scheduleID == schedule.id }
            .map(\.generationKey))
        var knownKeys = existingKeys
        var generated: [LedgerTransaction] = []
        var handledCount = 0

        while schedule.nextDueDate <= date,
              schedule.endDate.map({ schedule.nextDueDate <= $0 }) ?? true {
            guard handledCount < 500 else { throw RecurringScheduleError.generationLimitReached }
            handledCount += 1
            let dueDate = schedule.nextDueDate
            let key = AutomationGenerationKey.recurring(scheduleID: schedule.id, date: dueDate)
            guard let nextDate = RecurrenceDateCalculator.next(
                after: dueDate,
                frequency: schedule.frequency,
                interval: schedule.interval,
                anchorDate: schedule.anchorDate,
                calendar: calendar
            ) else {
                throw RecurringScheduleError.invalidDateRange
            }

            if knownKeys.contains(key) {
                schedule.nextDueDate = nextDate
                schedule.updatedAt = .now
                try context.save()
                continue
            }

            let draft = try codec.resolve(
                data: schedule.draftData,
                bookID: schedule.bookID,
                date: dueDate,
                wallets: wallets,
                categories: categories
            )
            schedule.nextDueDate = nextDate
            schedule.updatedAt = .now
            let transaction = try LedgerService(context: context).create(draft) { transaction in
                context.insert(RecurringOccurrence(
                    generationKey: key,
                    scheduleID: schedule.id,
                    scheduledDate: dueDate,
                    transactionID: transaction.id
                ))
            }
            knownKeys.insert(key)
            generated.append(transaction)
        }
        return generated
    }

    func setPaused(_ paused: Bool, schedule: RecurringSchedule) throws {
        schedule.isPaused = paused
        schedule.updatedAt = .now
        try context.save()
    }

    func setArchived(_ archived: Bool, schedule: RecurringSchedule) throws {
        schedule.isArchived = archived
        schedule.updatedAt = .now
        try context.save()
    }
}

enum AutomationGenerationKey {
    static func recurring(scheduleID: UUID, date: Date) -> String {
        "recurring|\(scheduleID.uuidString.lowercased())|\(milliseconds(date))"
    }

    static func installment(planID: UUID, index: Int) -> String {
        "installment|\(planID.uuidString.lowercased())|\(index)"
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}
