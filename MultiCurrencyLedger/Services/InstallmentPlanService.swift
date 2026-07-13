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

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入分期名称"
        case .invalidPrincipal: "分期本金必须大于 0"
        case .invalidFee: "分期手续费不能小于 0"
        case .invalidCount: "分期期数必须在 2 到 120 期之间"
        case .unrepresentableAmount: "金额的小数位超过当前币种支持范围"
        case .missingWallet: "分期引用的钱包已失效或被停用"
        case .invalidDestination: "账单分期必须选择同账本、同币种的信用账户"
        case .crossBookReference: "分期不能跨账本"
        case .invalidCategory: "消费分期只能使用当前账本的支出分类"
        case .generationLimitReached: "一次最多补生成 120 期"
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
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw InstallmentPlanError.emptyName }
        guard totalPrincipal > 0 else { throw InstallmentPlanError.invalidPrincipal }
        guard totalFee >= 0 else { throw InstallmentPlanError.invalidFee }
        guard (2...120).contains(installmentCount) else { throw InstallmentPlanError.invalidCount }
        guard sourceWallet.isEnabled,
              let bookID = sourceWallet.account?.book?.id else {
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
                $0.type == .expense && !$0.isArchived && ($0.bookID == nil || $0.bookID == bookID)
            }) ?? true else {
                throw InstallmentPlanError.invalidCategory
            }
        case .bill:
            guard let destinationWallet,
                  destinationWallet.isEnabled,
                  destinationWallet.id != sourceWallet.id,
                  destinationWallet.account?.book?.id == bookID else {
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
    func generateDue(
        for plan: InstallmentPlan,
        through date: Date = .now
    ) throws -> [LedgerTransaction] {
        guard !plan.isPaused, !plan.isArchived, !plan.isCompleted else { return [] }
        let wallets = try context.fetch(FetchDescriptor<CurrencyWallet>())
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        guard let source = wallets.first(where: {
            $0.id == plan.sourceWalletID && $0.isEnabled && $0.account?.book?.id == plan.bookID
        }) else { throw InstallmentPlanError.missingWallet }
        let destination = plan.destinationWalletID.flatMap { id in
            wallets.first { $0.id == id && $0.isEnabled && $0.account?.book?.id == plan.bookID }
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

            let detail = "第 \(index + 1)/\(plan.installmentCount) 期"
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
            let transaction = try LedgerService(context: context).create(draft) { transaction in
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
        guard !plan.isCompleted else { return }
        plan.isPaused = paused
        plan.updatedAt = .now
        try context.save()
    }

    /// Stops future generation without deleting already posted installments.
    func finishEarly(_ plan: InstallmentPlan, at date: Date = .now) throws {
        plan.completedAt = date
        plan.isPaused = false
        plan.updatedAt = date
        try context.save()
    }

    func setArchived(_ archived: Bool, plan: InstallmentPlan) throws {
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
