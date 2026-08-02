import Foundation
import SwiftData

enum InstallmentPlanError: LocalizedError, Equatable {
    case emptyName
    case invalidPrincipal
    case invalidFee
    case invalidCount
    case unrepresentableAmount
    case missingWallet
    case invalidDestination
    case crossBookReference
    case invalidCategory
    case generationLimitReached
    case foreignRepaymentWalletsRequired
    case foreignPlanRequired
    case installmentAlreadyCompleted

    var errorDescription: String? {
        switch self {
        case .emptyName: AppLocalization.string( "请输入分期名称")
        case .invalidPrincipal: AppLocalization.string( "分期本金必须大于 0")
        case .invalidFee: AppLocalization.string( "分期手续费不能小于 0")
        case .invalidCount: AppLocalization.string( "分期期数必须在 2 到 120 期之间")
        case .unrepresentableAmount: AppLocalization.string( "金额的小数位超过当前币种支持范围")
        case .missingWallet: AppLocalization.string( "分期引用的钱包已失效或被停用")
        case .invalidDestination: AppLocalization.string( "账单分期必须选择同账本、同币种的信用账户")
        case .crossBookReference: AppLocalization.string( "分期不能跨账本")
        case .invalidCategory: AppLocalization.string( "消费分期只能使用当前账本的支出分类")
        case .generationLimitReached: AppLocalization.string( "一次最多补生成 120 期")
        case .foreignRepaymentWalletsRequired: AppLocalization.string("外币分期需要不同币种的扣款钱包和信用卡钱包")
        case .foreignPlanRequired: AppLocalization.string("该分期不是外币还款计划")
        case .installmentAlreadyCompleted: AppLocalization.string("该分期计划已经完成")
        }
    }
}

struct InstallmentAllocator {
    static func allocations(
        total: Decimal,
        count: Int,
        fractionDigits: Int
    ) throws -> [Decimal] {
        guard total >= 0 else { throw InstallmentPlanError.invalidPrincipal }
        guard count > 0 else { throw InstallmentPlanError.invalidCount }
        var rounded = Decimal()
        var source = total
        NSDecimalRound(&rounded, &source, fractionDigits, .plain)
        guard rounded == total else { throw InstallmentPlanError.unrepresentableAmount }
        let divisor = Decimal(count)
        var base = Decimal()
        var quotient = total / divisor
        NSDecimalRound(&base, &quotient, fractionDigits, .down)
        guard count > 1 else { return [total] }
        return Array(repeating: base, count: count - 1)
            + [total - base * Decimal(count - 1)]
    }
}

@MainActor
final class InstallmentPlanService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func create(
        name: String,
        bookID: UUID,
        kind: InstallmentKind,
        totalPrincipal: Decimal,
        totalFee: Decimal = 0,
        installmentCount: Int,
        startDate: Date,
        sourceWallet: CurrencyWallet,
        destinationWallet: CurrencyWallet? = nil,
        category: LedgerCategory? = nil,
        sourceTransactionID: UUID? = nil,
        merchantOrCounterparty: String? = nil,
        note: String? = nil
    ) throws -> InstallmentPlan {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: bookID)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw InstallmentPlanError.emptyName }
        guard totalPrincipal > 0 else { throw InstallmentPlanError.invalidPrincipal }
        guard totalFee >= 0 else { throw InstallmentPlanError.invalidFee }
        guard (2...120).contains(installmentCount) else { throw InstallmentPlanError.invalidCount }
        guard sourceWallet.isEnabled,
              sourceWallet.account?.isArchived == false else {
            throw InstallmentPlanError.missingWallet
        }
        let fractionDigits = sourceWallet.currency?.fractionDigits ?? 2
        _ = try InstallmentAllocator.allocations(
            total: totalPrincipal, count: installmentCount, fractionDigits: fractionDigits
        )
        _ = try InstallmentAllocator.allocations(
            total: totalFee, count: installmentCount, fractionDigits: fractionDigits
        )

        switch kind {
        case .consumption:
            guard destinationWallet == nil else { throw InstallmentPlanError.invalidDestination }
            guard category.map({
                $0.type == .expense && !$0.isArchived
            }) ?? true else {
                throw InstallmentPlanError.invalidCategory
            }
        case .bill:
            guard let destinationWallet,
                  destinationWallet.isEnabled,
                  destinationWallet.account?.isArchived == false,
                  destinationWallet.id != sourceWallet.id else {
                throw InstallmentPlanError.crossBookReference
            }
            guard destinationWallet.currencyCode == sourceWallet.currencyCode,
                  destinationWallet.account?.type == .creditCard
                    || destinationWallet.account?.type == .payable else {
                throw InstallmentPlanError.invalidDestination
            }
        }

        let plan = InstallmentPlan(
            name: cleanName,
            bookID: bookID,
            kind: kind,
            totalPrincipal: totalPrincipal,
            totalFee: totalFee,
            installmentCount: installmentCount,
            startDate: startDate,
            sourceWalletID: sourceWallet.id,
            destinationWalletID: destinationWallet?.id,
            categoryID: kind == .consumption ? category?.id : nil,
            sourceTransactionID: sourceTransactionID,
            merchantOrCounterparty: merchantOrCounterparty?.trimmedOrNil,
            note: note?.trimmedOrNil,
            fractionDigits: fractionDigits
        )
        context.insert(plan)
        try context.save()
        return plan
    }

    @discardableResult
    func createForeignRepaymentPlanAndRecordFirst(
        name: String,
        bookID: UUID,
        installmentCount: Int,
        startDate: Date,
        settlementAmount: Decimal,
        sourceWallet: CurrencyWallet,
        destinationWallet: CurrencyWallet,
        feeAmount: Decimal? = nil,
        feeWallet: CurrencyWallet? = nil,
        discountAmount: Decimal? = nil,
        discountWallet: CurrencyWallet? = nil,
        note: String? = nil
    ) throws -> (plan: InstallmentPlan, transaction: LedgerTransaction) {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: bookID)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw InstallmentPlanError.emptyName }
        guard (2...120).contains(installmentCount) else { throw InstallmentPlanError.invalidCount }
        guard sourceWallet.isEnabled,
              destinationWallet.isEnabled,
              sourceWallet.account?.isArchived == false,
              destinationWallet.account?.isArchived == false,
              sourceWallet.currencyCode != destinationWallet.currencyCode,
              destinationWallet.account?.type == .creditCard else {
            throw InstallmentPlanError.foreignRepaymentWalletsRequired
        }
        let outstanding = max(Decimal.zero, -destinationWallet.balance)
        guard outstanding > 0 else { throw InstallmentPlanError.invalidPrincipal }
        let fractionDigits = SupportedCurrency.fractionDigits(for: destinationWallet.currencyCode)
        let principalParts = try InstallmentAllocator.allocations(
            total: outstanding,
            count: installmentCount,
            fractionDigits: fractionDigits
        )
        let plan = InstallmentPlan(
            name: cleanName,
            bookID: bookID,
            kind: .bill,
            totalPrincipal: outstanding,
            totalFee: 0,
            installmentCount: installmentCount,
            startDate: startDate,
            sourceWalletID: sourceWallet.id,
            destinationWalletID: destinationWallet.id,
            note: note,
            fractionDigits: fractionDigits,
            principalCurrencyCode: destinationWallet.currencyCode,
            settlementCurrencyCode: sourceWallet.currencyCode,
            isForeignCurrencyRepayment: true
        )
        context.insert(plan)
        do {
            let transaction = try recordForeignInstallment(
                for: plan,
                foreignPrincipal: principalParts[0],
                settlementAmount: settlementAmount,
                date: startDate,
                feeAmount: feeAmount,
                feeWallet: feeWallet,
                discountAmount: discountAmount,
                discountWallet: discountWallet
            )
            return (plan, transaction)
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    func recordForeignInstallment(
        for plan: InstallmentPlan,
        foreignPrincipal: Decimal,
        settlementAmount: Decimal,
        date: Date,
        feeAmount: Decimal? = nil,
        feeWallet: CurrencyWallet? = nil,
        discountAmount: Decimal? = nil,
        discountWallet: CurrencyWallet? = nil
    ) throws -> LedgerTransaction {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: plan.bookID)
        guard plan.isForeignCurrencyRepayment, plan.kind == .bill else {
            throw InstallmentPlanError.foreignPlanRequired
        }
        guard !plan.isCompleted else { throw InstallmentPlanError.installmentAlreadyCompleted }
        let wallets = try context.fetch(FetchDescriptor<CurrencyWallet>())
        guard let source = wallets.first(where: { $0.id == plan.sourceWalletID && $0.isEnabled }),
              let destinationID = plan.destinationWalletID,
              let destination = wallets.first(where: { $0.id == destinationID && $0.isEnabled }) else {
            throw InstallmentPlanError.missingWallet
        }
        let allocations = try InstallmentAllocator.allocations(
            total: plan.totalPrincipal,
            count: plan.installmentCount,
            fractionDigits: plan.fractionDigits
        )
        let index = plan.nextInstallmentIndex
        guard allocations.indices.contains(index),
              foreignPrincipal == allocations[index] else {
            throw InstallmentPlanError.invalidPrincipal
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let nextIndex = index + 1
        let nextDate = RecurrenceDateCalculator.next(
            after: plan.nextDueDate,
            frequency: .monthly,
            interval: 1,
            anchorDate: plan.startDate,
            calendar: calendar
        ) ?? plan.nextDueDate
        let oldIndex = plan.nextInstallmentIndex
        let oldNextDate = plan.nextDueDate
        let oldCompletedAt = plan.completedAt
        let oldUpdatedAt = plan.updatedAt
        let draft = TransactionDraft(
            type: .transfer,
            amount: settlementAmount,
            sourceWallet: source,
            destinationWallet: destination,
            destinationAmount: foreignPrincipal,
            feeAmount: feeAmount,
            feeWallet: feeWallet,
            date: date,
            note: plan.note,
            discountAmount: discountAmount,
            discountWallet: discountWallet,
            transferPurpose: .creditCardRepayment,
            settlementCurrencyCode: source.currencyCode,
            installmentPlanID: plan.id,
            installmentIndex: index
        )
        do {
            return try LedgerService(context: context).create(draft, bookID: plan.bookID) { transaction in
                plan.nextInstallmentIndex = nextIndex
                plan.nextDueDate = nextDate
                plan.completedAt = nextIndex >= plan.installmentCount ? .now : nil
                plan.updatedAt = .now
                context.insert(InstallmentOccurrence(
                    generationKey: AutomationGenerationKey.installment(planID: plan.id, index: index),
                    planID: plan.id,
                    installmentIndex: index,
                    scheduledDate: date,
                    principalAmount: foreignPrincipal,
                    feeAmount: feeAmount ?? 0,
                    transactionID: transaction.id
                ))
            }
        } catch {
            plan.nextInstallmentIndex = oldIndex
            plan.nextDueDate = oldNextDate
            plan.completedAt = oldCompletedAt
            plan.updatedAt = oldUpdatedAt
            throw error
        }
    }

    @discardableResult
    func generateDue(
        for plan: InstallmentPlan,
        through date: Date = .now
    ) throws -> [LedgerTransaction] {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: plan.bookID)
        guard !plan.isForeignCurrencyRepayment,
              !plan.isPaused, !plan.isArchived, !plan.isCompleted else { return [] }
        let wallets = try context.fetch(FetchDescriptor<CurrencyWallet>())
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        guard let source = wallets.first(where: {
            $0.id == plan.sourceWalletID && $0.isEnabled
                && $0.account?.isArchived == false
        }) else { throw InstallmentPlanError.missingWallet }
        let destination = plan.destinationWalletID.flatMap { id in
            wallets.first {
                $0.id == id && $0.isEnabled
                    && $0.account?.isArchived == false
            }
        }
        let category = plan.categoryID.flatMap { id in categories.first { $0.id == id && !$0.isArchived } }
        guard plan.kind != .bill || destination != nil else {
            throw InstallmentPlanError.invalidDestination
        }
        guard plan.kind != .consumption || plan.categoryID == nil || category != nil else {
            throw InstallmentPlanError.invalidCategory
        }
        let principalParts = try InstallmentAllocator.allocations(
            total: plan.totalPrincipal,
            count: plan.installmentCount,
            fractionDigits: plan.fractionDigits
        )
        let feeParts = try InstallmentAllocator.allocations(
            total: plan.totalFee,
            count: plan.installmentCount,
            fractionDigits: plan.fractionDigits
        )
        let existingKeys = Set(try context.fetch(FetchDescriptor<InstallmentOccurrence>())
            .filter { $0.planID == plan.id }
            .map(\.generationKey))
        var knownKeys = existingKeys
        var generated: [LedgerTransaction] = []
        var handledCount = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        while plan.nextInstallmentIndex < plan.installmentCount,
              plan.nextDueDate <= date {
            guard handledCount < 120 else { throw InstallmentPlanError.generationLimitReached }
            handledCount += 1
            let index = plan.nextInstallmentIndex
            let dueDate = plan.nextDueDate
            let principal = principalParts[index]
            let fee = feeParts[index]
            let key = AutomationGenerationKey.installment(planID: plan.id, index: index)
            let nextIndex = index + 1
            let nextDate = RecurrenceDateCalculator.next(
                after: dueDate,
                frequency: .monthly,
                interval: 1,
                anchorDate: plan.startDate,
                calendar: calendar
            ) ?? dueDate

            if knownKeys.contains(key) {
                updateProgress(plan, nextIndex: nextIndex, nextDate: nextDate)
                try context.save()
                continue
            }

            let detail = AppLocalization.string("第 \(index + 1)/\(plan.installmentCount) 期")
            let draft: TransactionDraft
            switch plan.kind {
            case .consumption:
                draft = TransactionDraft(
                    type: .expense,
                    amount: principal + fee,
                    sourceWallet: source,
                    date: dueDate,
                    note: [plan.note, detail].compactMap { $0 }.joined(separator: " · "),
                    merchantOrCounterparty: plan.merchantOrCounterparty,
                    category: category
                )
            case .bill:
                draft = TransactionDraft(
                    type: .transfer,
                    amount: principal,
                    sourceWallet: source,
                    destinationWallet: destination,
                    feeAmount: fee > 0 ? fee : nil,
                    feeWallet: fee > 0 ? source : nil,
                    date: dueDate,
                    note: [plan.note, detail].compactMap { $0 }.joined(separator: " · "),
                    merchantOrCounterparty: plan.merchantOrCounterparty
                )
            }
            updateProgress(plan, nextIndex: nextIndex, nextDate: nextDate)
            let transaction = try LedgerService(context: context).create(draft, bookID: plan.bookID) { transaction in
                context.insert(InstallmentOccurrence(
                    generationKey: key,
                    planID: plan.id,
                    installmentIndex: index,
                    scheduledDate: dueDate,
                    principalAmount: principal,
                    feeAmount: fee,
                    transactionID: transaction.id
                ))
            }
            knownKeys.insert(key)
            generated.append(transaction)
        }
        return generated
    }

    func setPaused(_ paused: Bool, plan: InstallmentPlan) throws {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: plan.bookID)
        guard !plan.isCompleted else { return }
        plan.isPaused = paused
        plan.updatedAt = .now
        try context.save()
    }

    /// Stops future generation without deleting already posted installments.
    func finishEarly(_ plan: InstallmentPlan, at date: Date = .now) throws {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: plan.bookID)
        plan.completedAt = date
        plan.isPaused = false
        plan.updatedAt = date
        try context.save()
    }

    func setArchived(_ archived: Bool, plan: InstallmentPlan) throws {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: plan.bookID)
        plan.isArchived = archived
        plan.updatedAt = .now
        try context.save()
    }

    private func updateProgress(_ plan: InstallmentPlan, nextIndex: Int, nextDate: Date) {
        plan.nextInstallmentIndex = nextIndex
        plan.nextDueDate = nextDate
        if nextIndex >= plan.installmentCount { plan.completedAt = .now }
        plan.updatedAt = .now
    }
}

private extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
