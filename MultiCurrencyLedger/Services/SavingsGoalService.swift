import Foundation
import SwiftData

enum SavingsGoalError: LocalizedError, Equatable {
    case emptyName
    case invalidTarget
    case invalidAllocation
    case insufficientAllocation
    case missingBook
    case invalidAccount

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入目标名称"
        case .invalidTarget: "目标金额必须大于 0"
        case .invalidAllocation: "分配金额不能为 0"
        case .insufficientAllocation: "取出金额不能超过当前已分配金额"
        case .missingBook: "存钱目标必须归属一个账本"
        case .invalidAccount: "关联账户不属于当前账本"
        }
    }
}

struct SavingsGoalProgress {
    let allocated: Decimal
    let target: Decimal
    let remaining: Decimal
    let fraction: Double
    let recommendedMonthlyAmount: Decimal?
}

@MainActor
final class SavingsGoalService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    @discardableResult
    func create(
        bookID: UUID,
        name: String,
        targetAmount: Decimal,
        currencyCode: String,
        targetDate: Date? = nil,
        symbolName: String = "target",
        colorHex: String = "3478F6"
    ) throws -> SavingsGoal {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw SavingsGoalError.emptyName }
        guard targetAmount > 0 else { throw SavingsGoalError.invalidTarget }
        guard try context.fetch(FetchDescriptor<LedgerBook>()).contains(where: { $0.id == bookID }) else {
            throw SavingsGoalError.missingBook
        }
        let goal = SavingsGoal(
            bookID: bookID,
            name: cleanName,
            targetAmount: targetAmount,
            currencyCode: currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            targetDate: targetDate,
            symbolName: symbolName,
            colorHex: colorHex
        )
        context.insert(goal)
        try context.save()
        return goal
    }

    func update(
        _ goal: SavingsGoal,
        name: String,
        targetAmount: Decimal,
        targetDate: Date?
    ) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw SavingsGoalError.emptyName }
        guard targetAmount > 0 else { throw SavingsGoalError.invalidTarget }
        goal.name = cleanName
        goal.targetAmount = targetAmount
        goal.targetDate = targetDate
        goal.updatedAt = .now
        try context.save()
    }

    @discardableResult
    func allocate(
        _ amount: Decimal,
        to goal: SavingsGoal,
        date: Date = .now,
        sourceAccountID: UUID? = nil,
        note: String? = nil
    ) throws -> SavingsAllocation {
        guard amount != 0 else { throw SavingsGoalError.invalidAllocation }
        if let sourceAccountID {
            guard try context.fetch(FetchDescriptor<Account>()).contains(where: {
                $0.id == sourceAccountID && $0.book?.id == goal.bookID
            }) else { throw SavingsGoalError.invalidAccount }
        }
        let current = goal.allocations.reduce(Decimal.zero) { $0 + $1.amount }
        guard current + amount >= 0 else { throw SavingsGoalError.insufficientAllocation }
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let allocation = SavingsAllocation(
            amount: amount,
            date: date,
            note: cleanNote?.isEmpty == true ? nil : cleanNote,
            sourceAccountID: sourceAccountID,
            goal: goal
        )
        context.insert(allocation)
        goal.updatedAt = .now
        try context.save()
        return allocation
    }

    func delete(_ allocation: SavingsAllocation) throws {
        allocation.goal?.updatedAt = .now
        context.delete(allocation)
        try context.save()
    }

    func setStatus(_ status: SavingsGoalStatus, goal: SavingsGoal) throws {
        goal.status = status
        goal.updatedAt = .now
        try context.save()
    }

    func progress(
        for goal: SavingsGoal,
        allocations: [SavingsAllocation],
        asOf date: Date = .now
    ) -> SavingsGoalProgress {
        let allocated = allocations.filter { $0.goal?.id == goal.id }.reduce(Decimal.zero) { $0 + $1.amount }
        let remaining = max(0, goal.targetAmount - allocated)
        let fraction = goal.targetAmount > 0
            ? NSDecimalNumber(decimal: allocated / goal.targetAmount).doubleValue
            : 0
        let recommendation: Decimal?
        if let targetDate = goal.targetDate, remaining > 0 {
            let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
            let end = calendar.dateInterval(of: .month, for: targetDate)?.start ?? targetDate
            let months = max(1, (calendar.dateComponents([.month], from: start, to: end).month ?? 0) + 1)
            recommendation = remaining / Decimal(months)
        } else {
            recommendation = nil
        }
        return SavingsGoalProgress(
            allocated: allocated,
            target: goal.targetAmount,
            remaining: remaining,
            fraction: fraction,
            recommendedMonthlyAmount: recommendation
        )
    }
}
