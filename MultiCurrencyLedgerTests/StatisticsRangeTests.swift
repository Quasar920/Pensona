import XCTest
@testable import MultiCurrencyLedger

final class StatisticsRangeTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    func testWeekMonthAndYearUseHalfOpenCalendarIntervals() {
        let now = date(2026, 7, 20, hour: 15)
        var state = StatisticsPageState(now: now, calendar: calendar)

        state.range = .week
        XCTAssertEqual(state.interval(calendar: calendar).start, date(2026, 7, 20))
        XCTAssertEqual(state.interval(calendar: calendar).end, date(2026, 7, 27))

        state.range = .month
        XCTAssertEqual(state.interval(calendar: calendar).start, date(2026, 7, 1))
        XCTAssertEqual(state.interval(calendar: calendar).end, date(2026, 8, 1))

        state.range = .year
        XCTAssertEqual(state.interval(calendar: calendar).start, date(2026, 1, 1))
        XCTAssertEqual(state.interval(calendar: calendar).end, date(2027, 1, 1))
    }

    func testCustomRangeIncludesWholeFinalDayAndNormalizesReverseInput() {
        var state = StatisticsPageState(now: date(2026, 7, 20), calendar: calendar)
        state.range = .custom
        state.customStart = date(2026, 7, 10, hour: 17)
        state.customEnd = date(2026, 7, 3, hour: 9)

        let interval = state.interval(calendar: calendar)
        XCTAssertEqual(interval.start, date(2026, 7, 3))
        XCTAssertEqual(interval.end, date(2026, 7, 11))
    }

    func testMovingPresetRangeDoesNotMutateCustomDates() {
        var state = StatisticsPageState(now: date(2026, 7, 20), calendar: calendar)
        let customStart = state.customStart
        let customEnd = state.customEnd
        state.range = .month
        state.moveRange(by: -1, calendar: calendar)

        XCTAssertEqual(state.interval(calendar: calendar).start, date(2026, 6, 1))
        XCTAssertEqual(state.customStart, customStart)
        XCTAssertEqual(state.customEnd, customEnd)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
