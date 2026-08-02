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
        case .emptyName: AppLocalization.string( "请输入目标名称")
        case .invalidTarget: AppLocalization.string( "目标金额必须大于 0")
        case .invalidAllocation: AppLocalization.string( "分配金额不能为 0")
        case .insufficientAllocation: AppLocalization.string( "取出金额不能超过当前已分配金额")
        case .missingBook: AppLocalization.string( "存钱目标必须归属一个账本")
        case .invalidAccount: AppLocalization.string( "关联账户不属于当前账本")
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

    /// Planning is global in V3. `bookID` remains on the model only as a
    /// compatibility/source value for older backups and stores.
    func allGoals(includeArchived: Bool = false) throws -> [SavingsGoal] {
        try context.fetch(FetchDescriptor<SavingsGoal>())
            .filter { $0.isGloballyVisible && (includeArchived || $0.status != .archived) }
            .sorted { $0.updatedAt > $1.updatedAt }
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
        do {
            _ = try LedgerBookAccess.requireActiveBook(in: context, id: bookID)
        } catch LedgerError.missingBook {
            throw SavingsGoalError.missingBook
        }
        let goal = SavingsGoal(
            bookID: bookID,
            name: cleanName,
            targetAmount: targetAmount,
            currencyCode: currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            targetDate: targetDate,
            symbolName: symbolName,
            colorHex: colorHex,
            isGloballyVisible: true
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
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: goal.bookID)
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
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: goal.bookID)
        guard amount != 0 else { throw SavingsGoalError.invalidAllocation }
        if let sourceAccountID {
            guard try context.fetch(FetchDescriptor<Account>()).contains(where: {
                $0.id == sourceAccountID && !$0.isArchived
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
        if let bookID = allocation.goal?.bookID {
            _ = try LedgerBookAccess.requireActiveBook(in: context, id: bookID)
        }
        allocation.goal?.updatedAt = .now
        context.delete(allocation)
        try context.save()
    }

    func setStatus(_ status: SavingsGoalStatus, goal: SavingsGoal) throws {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: goal.bookID)
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
