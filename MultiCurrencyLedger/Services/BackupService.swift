import Foundation
import SwiftData

struct BackupSettings: Codable, Equatable {
    var baseCurrencyCode: String
}

struct LedgerBackupDocument: Codable {
    static let currentVersion = 6

    var version: Int
    var exportedAt: Date
    var settings: BackupSettings
    var books: [BookBackup]
    var accounts: [AccountBackup]
    var wallets: [WalletBackup]
    var categories: [CategoryBackup]
    var tags: [TagBackup]
    var transactions: [TransactionBackup]
    var relations: [RelationBackup]
    var attachments: [AttachmentBackup]
    var templates: [TemplateBackup]
    var recurringSchedules: [RecurringScheduleBackup]
    var recurringOccurrences: [RecurringOccurrenceBackup]
    var installmentPlans: [InstallmentPlanBackup]
    var installmentOccurrences: [InstallmentOccurrenceBackup]
    var recognitionRecords: [RecognitionRecordBackup]
    var exchangeRates: [ExchangeRateBackup]
    var budgets: [BudgetBackup]
    var savingsGoals: [SavingsGoalBackup]
    var savingsAllocations: [SavingsAllocationBackup]
    var importBatches: [ImportBatchBackup]
    var importFingerprints: [ImportFingerprintBackup]
    var aaSplits: [AASplitBackup]
    var aaSettlements: [AASettlementBackup]

    init(
        version: Int = currentVersion,
        exportedAt: Date = .now,
        settings: BackupSettings,
        books: [BookBackup], accounts: [AccountBackup], wallets: [WalletBackup],
        categories: [CategoryBackup], tags: [TagBackup], transactions: [TransactionBackup],
        relations: [RelationBackup], attachments: [AttachmentBackup], templates: [TemplateBackup],
        recurringSchedules: [RecurringScheduleBackup], recurringOccurrences: [RecurringOccurrenceBackup],
        installmentPlans: [InstallmentPlanBackup], installmentOccurrences: [InstallmentOccurrenceBackup],
        recognitionRecords: [RecognitionRecordBackup], exchangeRates: [ExchangeRateBackup],
        budgets: [BudgetBackup], savingsGoals: [SavingsGoalBackup],
        savingsAllocations: [SavingsAllocationBackup], importBatches: [ImportBatchBackup],
        importFingerprints: [ImportFingerprintBackup], aaSplits: [AASplitBackup] = [],
        aaSettlements: [AASettlementBackup] = []
    ) {
        self.version = version; self.exportedAt = exportedAt; self.settings = settings
        self.books = books; self.accounts = accounts; self.wallets = wallets
        self.categories = categories; self.tags = tags; self.transactions = transactions
        self.relations = relations; self.attachments = attachments; self.templates = templates
        self.recurringSchedules = recurringSchedules; self.recurringOccurrences = recurringOccurrences
        self.installmentPlans = installmentPlans; self.installmentOccurrences = installmentOccurrences
        self.recognitionRecords = recognitionRecords; self.exchangeRates = exchangeRates
        self.budgets = budgets; self.savingsGoals = savingsGoals; self.savingsAllocations = savingsAllocations
        self.importBatches = importBatches; self.importFingerprints = importFingerprints
        self.aaSplits = aaSplits; self.aaSettlements = aaSettlements
    }

    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, settings, books, accounts, wallets, categories, tags, transactions
        case relations, attachments, templates, recurringSchedules, recurringOccurrences
        case installmentPlans, installmentOccurrences, recognitionRecords, exchangeRates
        case monthlyBudgets, budgets, savingsGoals, savingsAllocations, importBatches, importFingerprints
        case aaSplits, aaSettlements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
        settings = try c.decodeIfPresent(BackupSettings.self, forKey: .settings)
            ?? BackupSettings(baseCurrencyCode: SupportedCurrency.CNY.rawValue)
        books = try c.decodeIfPresent([BookBackup].self, forKey: .books) ?? []
        accounts = try c.decodeIfPresent([AccountBackup].self, forKey: .accounts) ?? []
        wallets = try c.decodeIfPresent([WalletBackup].self, forKey: .wallets) ?? []
        categories = try c.decodeIfPresent([CategoryBackup].self, forKey: .categories) ?? []
        tags = try c.decodeIfPresent([TagBackup].self, forKey: .tags) ?? []
        transactions = try c.decodeIfPresent([TransactionBackup].self, forKey: .transactions) ?? []
        relations = try c.decodeIfPresent([RelationBackup].self, forKey: .relations) ?? []
        attachments = try c.decodeIfPresent([AttachmentBackup].self, forKey: .attachments) ?? []
        templates = try c.decodeIfPresent([TemplateBackup].self, forKey: .templates) ?? []
        recurringSchedules = try c.decodeIfPresent([RecurringScheduleBackup].self, forKey: .recurringSchedules) ?? []
        recurringOccurrences = try c.decodeIfPresent([RecurringOccurrenceBackup].self, forKey: .recurringOccurrences) ?? []
        installmentPlans = try c.decodeIfPresent([InstallmentPlanBackup].self, forKey: .installmentPlans) ?? []
        installmentOccurrences = try c.decodeIfPresent([InstallmentOccurrenceBackup].self, forKey: .installmentOccurrences) ?? []
        recognitionRecords = try c.decodeIfPresent([RecognitionRecordBackup].self, forKey: .recognitionRecords) ?? []
        exchangeRates = try c.decodeIfPresent([ExchangeRateBackup].self, forKey: .exchangeRates) ?? []
        budgets = try c.decodeIfPresent([BudgetBackup].self, forKey: .budgets)
            ?? c.decodeIfPresent([BudgetBackup].self, forKey: .monthlyBudgets) ?? []
        savingsGoals = try c.decodeIfPresent([SavingsGoalBackup].self, forKey: .savingsGoals) ?? []
        savingsAllocations = try c.decodeIfPresent([SavingsAllocationBackup].self, forKey: .savingsAllocations) ?? []
        importBatches = try c.decodeIfPresent([ImportBatchBackup].self, forKey: .importBatches) ?? []
        importFingerprints = try c.decodeIfPresent([ImportFingerprintBackup].self, forKey: .importFingerprints) ?? []
        aaSplits = try c.decodeIfPresent([AASplitBackup].self, forKey: .aaSplits) ?? []
        aaSettlements = try c.decodeIfPresent([AASettlementBackup].self, forKey: .aaSettlements) ?? []
        if books.isEmpty, !accounts.isEmpty {
            let legacyBook = BookBackup(id: UUID(), name: "恢复的账本", sortOrder: 0, createdAt: exportedAt, updatedAt: exportedAt)
            books = [legacyBook]
            accounts = accounts.map {
                var value = $0
                value.bookID = legacyBook.id
                return value
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(exportedAt, forKey: .exportedAt)
        try c.encode(settings, forKey: .settings)
        try c.encode(books, forKey: .books)
        try c.encode(accounts, forKey: .accounts)
        try c.encode(wallets, forKey: .wallets)
        try c.encode(categories, forKey: .categories)
        try c.encode(transactions, forKey: .transactions)
        try c.encode(relations, forKey: .relations)
        try c.encode(attachments, forKey: .attachments)
        try c.encode(templates, forKey: .templates)
        try c.encode(recurringSchedules, forKey: .recurringSchedules)
        try c.encode(recurringOccurrences, forKey: .recurringOccurrences)
        try c.encode(installmentPlans, forKey: .installmentPlans)
        try c.encode(installmentOccurrences, forKey: .installmentOccurrences)
        try c.encode(recognitionRecords, forKey: .recognitionRecords)
        try c.encode(exchangeRates, forKey: .exchangeRates)
        try c.encode(budgets, forKey: .budgets)
        try c.encode(savingsGoals, forKey: .savingsGoals)
        try c.encode(savingsAllocations, forKey: .savingsAllocations)
        try c.encode(importBatches, forKey: .importBatches)
        try c.encode(importFingerprints, forKey: .importFingerprints)
        try c.encode(aaSplits, forKey: .aaSplits)
        try c.encode(aaSettlements, forKey: .aaSettlements)
    }
}

struct BookBackup: Codable { var id: UUID; var name: String; var sortOrder: Int; var createdAt: Date; var updatedAt: Date }
struct AccountBackup: Codable {
    var id: UUID; var bookID: UUID?; var name: String; var type: String; var note: String?
    var isHidden: Bool; var isArchived: Bool?; var sortOrder: Int; var createdAt: Date; var updatedAt: Date
    private enum CodingKeys: String, CodingKey { case id, bookID, name, type, note, isHidden, isArchived, sortOrder, createdAt, updatedAt }
}
struct WalletBackup: Codable {
    var id: UUID; var accountID: UUID?; var currencyCode: String; var balance: Decimal
    var isEnabled: Bool; var createdAt: Date; var updatedAt: Date
}
struct CategoryBackup: Codable {
    var id: UUID; var name: String; var type: String; var symbolName: String; var sortOrder: Int
    var isSystem: Bool; var bookID: UUID?; var parentID: UUID?; var isArchived: Bool?
    var createdAt: Date?; var updatedAt: Date?
}
struct TagBackup: Codable {
    var id: UUID; var name: String; var bookID: UUID; var colorHex: String; var isArchived: Bool
    var createdAt: Date; var updatedAt: Date
}
struct PaymentPartBackup: Codable { var id: UUID; var walletID: UUID?; var amount: Decimal; var sortOrder: Int; var createdAt: Date }
struct TransactionBackup: Codable {
    var id: UUID; var type: String; var date: Date; var note: String?; var createdAt: Date; var updatedAt: Date
    var amount: Decimal?; var currencyCode: String?; var sourceAccountID: UUID?; var sourceWalletID: UUID?
    var destinationAccountID: UUID?; var destinationWalletID: UUID?; var sourceAmount: Decimal?
    var sourceCurrencyCode: String?; var destinationAmount: Decimal?; var destinationCurrencyCode: String?
    var feeAmount: Decimal?; var feeCurrencyCode: String?; var feeWalletID: UUID?; var exchangeRate: Decimal?
    var adjustmentDirection: String?; var adjustmentReason: String?; var categoryID: UUID?
    var tagIDs: [UUID]?; var paymentParts: [PaymentPartBackup]?; var merchantOrCounterparty: String?
    var originalAmount: Decimal?; var discountAmount: Decimal?; var recognitionImportID: UUID?
}
struct RelationBackup: Codable {
    var id: UUID; var kind: String; var originalTransactionID: UUID; var relatedTransactionID: UUID
    var amount: Decimal; var createdAt: Date
}
struct AASplitBackup: Codable {
    var id: UUID; var originalTransactionID: UUID; var otherPeopleCount: Int
    var calculationMode: String; var othersOwedAmount: Decimal; var note: String?
    var createdAt: Date; var updatedAt: Date
}
struct AASettlementBackup: Codable {
    var id: UUID; var splitID: UUID; var recoveryTransactionID: UUID
    var amount: Decimal; var createdAt: Date
}
struct AttachmentBackup: Codable {
    var id: UUID; var transactionID: UUID; var bookID: UUID; var relativePath: String
    var originalFilename: String; var mimeType: String; var byteCount: Int; var createdAt: Date; var data: Data?
}
struct TemplateBackup: Codable {
    var id: UUID; var name: String; var bookID: UUID; var type: String; var amount: Decimal
    var sourceWalletID: UUID; var destinationWalletID: UUID?; var destinationAmount: Decimal?
    var feeAmount: Decimal?; var feeWalletID: UUID?; var categoryID: UUID?; var tagIDs: [UUID]
    var paymentParts: [TemplatePaymentPartReference]; var note: String?; var merchantOrCounterparty: String?
    var adjustmentDirection: String?; var adjustmentReason: String?; var isArchived: Bool
    var createdAt: Date; var updatedAt: Date
}
struct RecurringScheduleBackup: Codable {
    var id: UUID; var name: String; var bookID: UUID; var frequency: String; var interval: Int
    var anchorDate: Date; var nextDueDate: Date; var endDate: Date?; var timeZoneIdentifier: String
    var draftData: Data; var isPaused: Bool; var isArchived: Bool; var createdAt: Date; var updatedAt: Date
}
struct RecurringOccurrenceBackup: Codable {
    var id: UUID; var generationKey: String; var scheduleID: UUID; var scheduledDate: Date
    var transactionID: UUID; var createdAt: Date
}
struct InstallmentPlanBackup: Codable {
    var id: UUID; var name: String; var bookID: UUID; var kind: String; var totalPrincipal: Decimal
    var totalFee: Decimal; var installmentCount: Int; var nextInstallmentIndex: Int; var startDate: Date
    var nextDueDate: Date; var sourceWalletID: UUID; var destinationWalletID: UUID?; var categoryID: UUID?
    var sourceTransactionID: UUID?; var merchantOrCounterparty: String?; var note: String?
    var fractionDigits: Int; var isPaused: Bool; var isArchived: Bool; var completedAt: Date?
    var createdAt: Date; var updatedAt: Date
}
struct InstallmentOccurrenceBackup: Codable {
    var id: UUID; var generationKey: String; var planID: UUID; var installmentIndex: Int
    var scheduledDate: Date; var principalAmount: Decimal; var feeAmount: Decimal
    var transactionID: UUID; var createdAt: Date
}
struct RecognitionRecordBackup: Codable {
    var id: UUID; var createdAt: Date; var status: String; var decisionReason: String; var candidateType: String
    var bookID: UUID; var paidAmount: Decimal; var currencyCode: String; var occurredAt: Date
    var merchantOrCounterparty: String?; var note: String?; var originalAmount: Decimal?
    var discountAmount: Decimal; var feeAmount: Decimal; var sourceAccountHint: String?
    var categoryCandidate: String?; var selectedWalletID: UUID?; var selectedCategoryID: UUID?
    var transactionFingerprint: String; var transactionID: UUID?
}
struct ExchangeRateBackup: Codable {
    var id: UUID; var currencyCode: String; var baseCurrencyCode: String; var rate: Decimal
    var source: String; var updatedAt: Date
}
struct BudgetBackup: Codable {
    var id: UUID; var scopeKey: String?; var bookID: UUID; var monthStart: Date; var currencyCode: String
    var amount: Decimal; var period: String?; var categoryID: UUID?; var createdAt: Date; var updatedAt: Date
}
struct SavingsGoalBackup: Codable {
    var id: UUID; var bookID: UUID; var name: String; var targetAmount: Decimal; var currencyCode: String
    var targetDate: Date?; var symbolName: String; var colorHex: String; var status: String
    var createdAt: Date; var updatedAt: Date
}
struct SavingsAllocationBackup: Codable {
    var id: UUID; var goalID: UUID?; var amount: Decimal; var date: Date; var note: String?
    var sourceAccountID: UUID?; var createdAt: Date
}
struct ImportBatchBackup: Codable {
    var id: UUID; var sourceName: String; var preset: String; var bookID: UUID; var rowCount: Int
    var importedCount: Int; var skippedCount: Int; var errorCount: Int; var createdAt: Date
    var completedAt: Date?; var undoneAt: Date?
}
struct ImportFingerprintBackup: Codable {
    var id: UUID; var value: String; var batchID: UUID; var transactionID: UUID; var createdAt: Date
}

struct BackupPreview {
    let version: Int
    let exportedAt: Date
    let bookCount: Int
    let accountCount: Int
    let transactionCount: Int
    let attachmentCount: Int
    let baseCurrencyCode: String
    let warnings: [String]
}

struct BackupRestoreResult {
    let settings: BackupSettings
    let recoveryURL: URL
    let warnings: [String]
}

enum BackupServiceError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidCurrency(String)
    case duplicateID(String)
    case brokenReference(String)
    case unsafeAttachmentPath

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "备份版本 \(version) 高于当前 App 支持的版本"
        case .invalidCurrency(let code): "备份包含不受支持的币种：\(code)"
        case .duplicateID(let type): "备份中的 \(type) 存在重复标识"
        case .brokenReference(let detail): "备份引用不完整：\(detail)"
        case .unsafeAttachmentPath: "备份包含不安全的附件路径"
        }
    }
}

@MainActor
enum BackupService {
    static func makeDocument(
        context: ModelContext,
        baseCurrencyCode: String,
        attachmentStore: AttachmentStore = AttachmentStore()
    ) throws -> LedgerBackupDocument {
        let attachments = try context.fetch(FetchDescriptor<TransactionAttachment>()).map { value in
            let data = try? Data(contentsOf: attachmentStore.url(for: value.relativePath), options: .mappedIfSafe)
            return AttachmentBackup(
                id: value.id, transactionID: value.transactionID, bookID: value.bookID,
                relativePath: value.relativePath, originalFilename: value.originalFilename,
                mimeType: value.mimeType, byteCount: value.byteCount, createdAt: value.createdAt, data: data
            )
        }
        return LedgerBackupDocument(
            settings: BackupSettings(baseCurrencyCode: baseCurrencyCode),
            books: try context.fetch(FetchDescriptor<LedgerBook>()).map {
                BookBackup(id: $0.id, name: $0.name, sortOrder: $0.sortOrder, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            accounts: try context.fetch(FetchDescriptor<Account>()).map {
                AccountBackup(id: $0.id, bookID: $0.book?.id, name: $0.name, type: $0.typeRawValue, note: $0.note,
                              isHidden: $0.isHidden, isArchived: $0.isArchived, sortOrder: $0.sortOrder,
                              createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            wallets: try context.fetch(FetchDescriptor<CurrencyWallet>()).map {
                WalletBackup(id: $0.id, accountID: $0.account?.id, currencyCode: $0.currencyCode, balance: $0.balance,
                             isEnabled: $0.isEnabled, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            categories: try context.fetch(FetchDescriptor<LedgerCategory>()).map {
                CategoryBackup(id: $0.id, name: $0.name, type: $0.typeRawValue, symbolName: $0.symbolName,
                               sortOrder: $0.sortOrder, isSystem: $0.isSystem, bookID: $0.bookID, parentID: $0.parentID,
                               isArchived: $0.isArchived, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            tags: [],
            transactions: try context.fetch(FetchDescriptor<LedgerTransaction>()).map(transactionBackup),
            relations: try context.fetch(FetchDescriptor<TransactionRelation>()).map {
                RelationBackup(id: $0.id, kind: $0.kindRawValue, originalTransactionID: $0.originalTransactionID,
                               relatedTransactionID: $0.relatedTransactionID, amount: $0.amount, createdAt: $0.createdAt)
            },
            attachments: attachments,
            templates: try context.fetch(FetchDescriptor<TransactionTemplate>()).map {
                TemplateBackup(id: $0.id, name: $0.name, bookID: $0.bookID, type: $0.typeRawValue, amount: $0.amount,
                               sourceWalletID: $0.sourceWalletID, destinationWalletID: $0.destinationWalletID,
                               destinationAmount: $0.destinationAmount, feeAmount: $0.feeAmount,
                               feeWalletID: $0.feeWalletID, categoryID: $0.categoryID, tagIDs: [],
                               paymentParts: $0.paymentPartReferences, note: $0.note,
                               merchantOrCounterparty: $0.merchantOrCounterparty,
                               adjustmentDirection: $0.adjustmentDirectionRawValue, adjustmentReason: $0.adjustmentReason,
                               isArchived: $0.isArchived, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            recurringSchedules: try context.fetch(FetchDescriptor<RecurringSchedule>()).map {
                RecurringScheduleBackup(id: $0.id, name: $0.name, bookID: $0.bookID, frequency: $0.frequencyRawValue,
                                        interval: $0.interval, anchorDate: $0.anchorDate, nextDueDate: $0.nextDueDate,
                                        endDate: $0.endDate, timeZoneIdentifier: $0.timeZoneIdentifier, draftData: $0.draftData,
                                        isPaused: $0.isPaused, isArchived: $0.isArchived,
                                        createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            recurringOccurrences: try context.fetch(FetchDescriptor<RecurringOccurrence>()).map {
                RecurringOccurrenceBackup(id: $0.id, generationKey: $0.generationKey, scheduleID: $0.scheduleID,
                                          scheduledDate: $0.scheduledDate, transactionID: $0.transactionID, createdAt: $0.createdAt)
            },
            installmentPlans: try context.fetch(FetchDescriptor<InstallmentPlan>()).map {
                InstallmentPlanBackup(id: $0.id, name: $0.name, bookID: $0.bookID, kind: $0.kindRawValue,
                                      totalPrincipal: $0.totalPrincipal, totalFee: $0.totalFee,
                                      installmentCount: $0.installmentCount, nextInstallmentIndex: $0.nextInstallmentIndex,
                                      startDate: $0.startDate, nextDueDate: $0.nextDueDate, sourceWalletID: $0.sourceWalletID,
                                      destinationWalletID: $0.destinationWalletID, categoryID: $0.categoryID,
                                      sourceTransactionID: $0.sourceTransactionID,
                                      merchantOrCounterparty: $0.merchantOrCounterparty, note: $0.note,
                                      fractionDigits: $0.fractionDigits, isPaused: $0.isPaused, isArchived: $0.isArchived,
                                      completedAt: $0.completedAt, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            installmentOccurrences: try context.fetch(FetchDescriptor<InstallmentOccurrence>()).map {
                InstallmentOccurrenceBackup(id: $0.id, generationKey: $0.generationKey, planID: $0.planID,
                                            installmentIndex: $0.installmentIndex, scheduledDate: $0.scheduledDate,
                                            principalAmount: $0.principalAmount, feeAmount: $0.feeAmount,
                                            transactionID: $0.transactionID, createdAt: $0.createdAt)
            },
            recognitionRecords: try context.fetch(FetchDescriptor<RecognitionImportRecord>()).map {
                RecognitionRecordBackup(id: $0.id, createdAt: $0.createdAt, status: $0.statusRawValue,
                                        decisionReason: $0.decisionReasonRawValue, candidateType: $0.candidateTypeRawValue,
                                        bookID: $0.bookID, paidAmount: $0.paidAmount, currencyCode: $0.currencyCode,
                                        occurredAt: $0.occurredAt, merchantOrCounterparty: $0.merchantOrCounterparty,
                                        note: $0.note, originalAmount: $0.originalAmount,
                                        discountAmount: $0.discountAmount, feeAmount: $0.feeAmount,
                                        sourceAccountHint: $0.sourceAccountHint, categoryCandidate: $0.categoryCandidate,
                                        selectedWalletID: $0.selectedWalletID, selectedCategoryID: $0.selectedCategoryID,
                                        transactionFingerprint: $0.transactionFingerprint, transactionID: $0.transactionID)
            },
            exchangeRates: try context.fetch(FetchDescriptor<ExchangeRate>()).map {
                ExchangeRateBackup(id: $0.id, currencyCode: $0.currencyCode, baseCurrencyCode: $0.baseCurrencyCode,
                                   rate: $0.rate, source: $0.sourceRawValue, updatedAt: $0.updatedAt)
            },
            budgets: try context.fetch(FetchDescriptor<MonthlyBudget>()).map {
                BudgetBackup(id: $0.id, scopeKey: $0.scopeKey, bookID: $0.bookID, monthStart: $0.monthStart,
                             currencyCode: $0.currencyCode, amount: $0.amount, period: $0.periodRawValue,
                             categoryID: $0.categoryID, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            savingsGoals: try context.fetch(FetchDescriptor<SavingsGoal>()).map {
                SavingsGoalBackup(id: $0.id, bookID: $0.bookID, name: $0.name, targetAmount: $0.targetAmount,
                                  currencyCode: $0.currencyCode, targetDate: $0.targetDate, symbolName: $0.symbolName,
                                  colorHex: $0.colorHex, status: $0.statusRawValue,
                                  createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            savingsAllocations: try context.fetch(FetchDescriptor<SavingsAllocation>()).map {
                SavingsAllocationBackup(id: $0.id, goalID: $0.goal?.id, amount: $0.amount, date: $0.date,
                                        note: $0.note, sourceAccountID: $0.sourceAccountID, createdAt: $0.createdAt)
            },
            importBatches: try context.fetch(FetchDescriptor<TransactionImportBatch>()).map {
                ImportBatchBackup(id: $0.id, sourceName: $0.sourceName, preset: $0.presetRawValue,
                                  bookID: $0.bookID, rowCount: $0.rowCount, importedCount: $0.importedCount,
                                  skippedCount: $0.skippedCount, errorCount: $0.errorCount, createdAt: $0.createdAt,
                                  completedAt: $0.completedAt, undoneAt: $0.undoneAt)
            },
            importFingerprints: try context.fetch(FetchDescriptor<TransactionImportFingerprint>()).map {
                ImportFingerprintBackup(id: $0.id, value: $0.value, batchID: $0.batchID,
                                        transactionID: $0.transactionID, createdAt: $0.createdAt)
            },
            aaSplits: try context.fetch(FetchDescriptor<AASplit>()).map {
                AASplitBackup(
                    id: $0.id,
                    originalTransactionID: $0.originalTransactionID,
                    otherPeopleCount: $0.otherPeopleCount,
                    calculationMode: $0.calculationModeRawValue,
                    othersOwedAmount: $0.othersOwedAmount,
                    note: $0.note,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            aaSettlements: try context.fetch(FetchDescriptor<AASettlement>()).map {
                AASettlementBackup(
                    id: $0.id,
                    splitID: $0.splitID,
                    recoveryTransactionID: $0.recoveryTransactionID,
                    amount: $0.amount,
                    createdAt: $0.createdAt
                )
            }
        )
    }

    static func encode(_ document: LedgerBackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> LedgerBackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LedgerBackupDocument.self, from: data)
    }

    static func makeBackupFile(context: ModelContext, baseCurrencyCode: String) throws -> URL {
        let document = try makeDocument(context: context, baseCurrencyCode: baseCurrencyCode)
        let data = try encode(document)
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiCurrencyLedger-Full-Backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func preview(data: Data) throws -> BackupPreview {
        let document = try decode(data)
        let warnings = try validate(document)
        return BackupPreview(
            version: document.version, exportedAt: document.exportedAt,
            bookCount: document.books.count, accountCount: document.accounts.count,
            transactionCount: document.transactions.count, attachmentCount: document.attachments.count,
            baseCurrencyCode: document.settings.baseCurrencyCode, warnings: warnings
        )
    }

    static func restore(
        data: Data,
        context: ModelContext,
        currentBaseCurrencyCode: String,
        attachmentStore: AttachmentStore = AttachmentStore()
    ) throws -> BackupRestoreResult {
        let document = try decode(data)
        let warnings = try validate(document)
        let current = try makeDocument(context: context, baseCurrencyCode: currentBaseCurrencyCode, attachmentStore: attachmentStore)
        let recoveryURL = try writeRecovery(try encode(current))
        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory.appendingPathComponent("mcl-restore-\(UUID())", isDirectory: true)
        let previousRoot = fileManager.temporaryDirectory.appendingPathComponent("mcl-previous-\(UUID())", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        do {
            try stageAttachments(document.attachments, at: stagingRoot)
            try fileManager.createDirectory(at: attachmentStore.rootURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: attachmentStore.rootURL.path) {
                try fileManager.moveItem(at: attachmentStore.rootURL, to: previousRoot)
            }
            try fileManager.moveItem(at: stagingRoot, to: attachmentStore.rootURL)
            do {
                try replaceDatabase(with: document, context: context)
                try? fileManager.removeItem(at: previousRoot)
            } catch {
                context.rollback()
                try? fileManager.removeItem(at: attachmentStore.rootURL)
                if fileManager.fileExists(atPath: previousRoot.path) {
                    try? fileManager.moveItem(at: previousRoot, to: attachmentStore.rootURL)
                }
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
        return BackupRestoreResult(settings: document.settings, recoveryURL: recoveryURL, warnings: warnings)
    }

    private static func transactionBackup(_ value: LedgerTransaction) -> TransactionBackup {
        TransactionBackup(
            id: value.id, type: value.typeRawValue, date: value.date, note: value.note,
            createdAt: value.createdAt, updatedAt: value.updatedAt, amount: value.amount,
            currencyCode: value.currencyCode, sourceAccountID: value.sourceAccount?.id,
            sourceWalletID: value.sourceWallet?.id, destinationAccountID: value.destinationAccount?.id,
            destinationWalletID: value.destinationWallet?.id, sourceAmount: value.sourceAmount,
            sourceCurrencyCode: value.sourceCurrencyCode, destinationAmount: value.destinationAmount,
            destinationCurrencyCode: value.destinationCurrencyCode, feeAmount: value.feeAmount,
            feeCurrencyCode: value.feeCurrencyCode, feeWalletID: value.feeWallet?.id,
            exchangeRate: value.exchangeRate, adjustmentDirection: value.adjustmentDirectionRawValue,
            adjustmentReason: value.adjustmentReason, categoryID: value.category?.id,
            tagIDs: nil, paymentParts: value.paymentParts.map {
                PaymentPartBackup(id: $0.id, walletID: $0.wallet?.id, amount: $0.amount,
                                  sortOrder: $0.sortOrder, createdAt: $0.createdAt)
            }, merchantOrCounterparty: value.merchantOrCounterparty, originalAmount: value.originalAmount,
            discountAmount: value.discountAmount, recognitionImportID: value.recognitionImportID
        )
    }

    private static func validate(_ document: LedgerBackupDocument) throws -> [String] {
        guard document.version <= LedgerBackupDocument.currentVersion else {
            throw BackupServiceError.unsupportedVersion(document.version)
        }
        let codes = [document.settings.baseCurrencyCode]
            + document.wallets.map(\.currencyCode)
            + document.exchangeRates.flatMap { [$0.currencyCode, $0.baseCurrencyCode] }
            + document.budgets.map(\.currencyCode) + document.savingsGoals.map(\.currencyCode)
        if let invalid = codes.first(where: { SupportedCurrency(rawValue: $0) == nil }) {
            throw BackupServiceError.invalidCurrency(invalid)
        }
        try requireUnique(document.books.map(\.id), "账本")
        try requireUnique(document.accounts.map(\.id), "账户")
        try requireUnique(document.wallets.map(\.id), "钱包")
        try requireUnique(document.transactions.map(\.id), "流水")
        try requireUnique(document.aaSplits.map(\.id), "AA 分摊")
        try requireUnique(document.aaSplits.map(\.originalTransactionID), "AA 原支出")
        try requireUnique(document.aaSettlements.map(\.id), "AA 收款")
        try requireUnique(document.aaSettlements.map(\.recoveryTransactionID), "AA 收款流水")
        try requireUnique(document.importFingerprints.map(\.value), "导入指纹")
        let bookIDs = Set(document.books.map(\.id))
        let accountIDs = Set(document.accounts.map(\.id))
        let walletIDs = Set(document.wallets.map(\.id))
        let transactionIDs = Set(document.transactions.map(\.id))
        let transactionByID = Dictionary(uniqueKeysWithValues: document.transactions.map { ($0.id, $0) })
        let aaSplitIDs = Set(document.aaSplits.map(\.id))
        let categoryIDs = Set(document.categories.map(\.id))
        let scheduleIDs = Set(document.recurringSchedules.map(\.id))
        let planIDs = Set(document.installmentPlans.map(\.id))
        let goalIDs = Set(document.savingsGoals.map(\.id))
        let importBatchIDs = Set(document.importBatches.map(\.id))
        for account in document.accounts where account.bookID.map({ !bookIDs.contains($0) }) == true {
            throw BackupServiceError.brokenReference("账户 \(account.name) 的账本不存在")
        }
        for wallet in document.wallets where wallet.accountID.map({ !accountIDs.contains($0) }) == true {
            throw BackupServiceError.brokenReference("钱包 \(wallet.currencyCode) 的账户不存在")
        }
        if document.categories.contains(where: { $0.bookID.map { !bookIDs.contains($0) } == true }) {
            throw BackupServiceError.brokenReference("分类的账本不存在")
        }
        for transaction in document.transactions {
            let referencedWallets = [transaction.sourceWalletID, transaction.destinationWalletID, transaction.feeWalletID]
                + (transaction.paymentParts ?? []).map(\.walletID)
            if referencedWallets.compactMap({ $0 }).contains(where: { !walletIDs.contains($0) }) {
                throw BackupServiceError.brokenReference("流水 \(transaction.id) 的钱包不存在")
            }
            if transaction.categoryID.map({ !categoryIDs.contains($0) }) == true {
                throw BackupServiceError.brokenReference("流水 \(transaction.id) 的分类不存在")
            }
            if [transaction.sourceAccountID, transaction.destinationAccountID].compactMap({ $0 })
                .contains(where: { !accountIDs.contains($0) }) {
                throw BackupServiceError.brokenReference("流水 \(transaction.id) 的账户不存在")
            }
        }
        for relation in document.relations where
            !transactionIDs.contains(relation.originalTransactionID) || !transactionIDs.contains(relation.relatedTransactionID) {
            throw BackupServiceError.brokenReference("退款或报销关系指向不存在的流水")
        }
        let recoveryOriginalIDs = Set(document.relations.map(\.originalTransactionID))
        for split in document.aaSplits {
            guard let original = transactionByID[split.originalTransactionID],
                  original.type == TransactionKind.expense.rawValue,
                  split.otherPeopleCount > 0,
                  AASplitCalculationMode(rawValue: split.calculationMode) != nil else {
                throw BackupServiceError.brokenReference("AA 分摊指向的原支出或计算方式无效")
            }
            let total = original.sourceAmount ?? original.amount ?? 0
            guard split.othersOwedAmount > 0,
                  split.othersOwedAmount <= total,
                  !recoveryOriginalIDs.contains(split.originalTransactionID) else {
                throw BackupServiceError.brokenReference("AA 分摊金额无效或与退款报销冲突")
            }
            let collected = document.aaSettlements
                .filter { $0.splitID == split.id }
                .reduce(Decimal.zero) { $0 + $1.amount }
            guard collected <= split.othersOwedAmount else {
                throw BackupServiceError.brokenReference("AA 累计收款超过应收金额")
            }
        }
        for settlement in document.aaSettlements {
            guard aaSplitIDs.contains(settlement.splitID),
                  transactionIDs.contains(settlement.recoveryTransactionID),
                  settlement.amount > 0 else {
                throw BackupServiceError.brokenReference("AA 收款指向不存在的分摊或流水")
            }
        }
        for attachment in document.attachments {
            guard transactionIDs.contains(attachment.transactionID), bookIDs.contains(attachment.bookID) else {
                throw BackupServiceError.brokenReference("附件指向不存在的账本或流水")
            }
            let components = attachment.relativePath.split(separator: "/")
            guard !attachment.relativePath.hasPrefix("/"), !components.isEmpty, !components.contains("..") else {
                throw BackupServiceError.unsafeAttachmentPath
            }
        }
        for template in document.templates {
            let referencedWallets = [template.sourceWalletID] + [template.destinationWalletID, template.feeWalletID].compactMap { $0 }
                + template.paymentParts.map(\.walletID)
            guard bookIDs.contains(template.bookID),
                  !referencedWallets.contains(where: { !walletIDs.contains($0) }),
                  template.categoryID.map({ categoryIDs.contains($0) }) ?? true else {
                throw BackupServiceError.brokenReference("模板 \(template.name) 的引用不存在")
            }
        }
        if document.recurringSchedules.contains(where: { !bookIDs.contains($0.bookID) })
            || document.recurringOccurrences.contains(where: {
                !scheduleIDs.contains($0.scheduleID) || !transactionIDs.contains($0.transactionID)
            }) {
            throw BackupServiceError.brokenReference("周期记账引用不存在")
        }
        for plan in document.installmentPlans {
            guard bookIDs.contains(plan.bookID), walletIDs.contains(plan.sourceWalletID),
                  plan.destinationWalletID.map({ walletIDs.contains($0) }) ?? true,
                  plan.categoryID.map({ categoryIDs.contains($0) }) ?? true,
                  plan.sourceTransactionID.map({ transactionIDs.contains($0) }) ?? true else {
                throw BackupServiceError.brokenReference("分期计划 \(plan.name) 的引用不存在")
            }
        }
        if document.installmentOccurrences.contains(where: {
            !planIDs.contains($0.planID) || !transactionIDs.contains($0.transactionID)
        }) {
            throw BackupServiceError.brokenReference("分期记录引用不存在")
        }
        if document.budgets.contains(where: {
            !bookIDs.contains($0.bookID) || ($0.categoryID.map { !categoryIDs.contains($0) } ?? false)
        }) || document.savingsGoals.contains(where: { !bookIDs.contains($0.bookID) }) {
            throw BackupServiceError.brokenReference("预算或存钱目标的账本不存在")
        }
        if document.savingsAllocations.contains(where: {
            ($0.goalID.map { !goalIDs.contains($0) } ?? false)
                || ($0.sourceAccountID.map { !accountIDs.contains($0) } ?? false)
        }) {
            throw BackupServiceError.brokenReference("存钱分配引用不存在")
        }
        if document.importBatches.contains(where: { !bookIDs.contains($0.bookID) })
            || document.importFingerprints.contains(where: {
                !importBatchIDs.contains($0.batchID) || !transactionIDs.contains($0.transactionID)
            }) {
            throw BackupServiceError.brokenReference("导入批次引用不存在")
        }
        var warnings: [String] = []
        let missingAttachments = document.attachments.filter { $0.data == nil }.count
        if missingAttachments > 0 { warnings.append("\(missingAttachments) 个附件只有索引、没有文件内容") }
        if document.version < LedgerBackupDocument.currentVersion {
            warnings.append("旧版备份将迁移到版本 \(LedgerBackupDocument.currentVersion)")
        }
        return warnings
    }

    private static func requireUnique<T: Hashable>(_ values: [T], _ type: String) throws {
        guard Set(values).count == values.count else { throw BackupServiceError.duplicateID(type) }
    }

    private static func writeRecovery(_ data: Data) throws -> URL {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let folder = support.appendingPathComponent("MultiCurrencyLedger/Recovery", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = folder.appendingPathComponent("pre-restore-\(formatter.string(from: .now)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func stageAttachments(_ attachments: [AttachmentBackup], at root: URL) throws {
        let manager = FileManager.default
        for attachment in attachments {
            guard let data = attachment.data else { continue }
            let components = attachment.relativePath.split(separator: "/")
            guard !attachment.relativePath.hasPrefix("/"), !components.isEmpty, !components.contains("..") else {
                throw BackupServiceError.unsafeAttachmentPath
            }
            let destination = root.appendingPathComponent(attachment.relativePath).standardizedFileURL
            guard destination.path.hasPrefix(root.standardizedFileURL.path + "/") else {
                throw BackupServiceError.unsafeAttachmentPath
            }
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
    }
}

private extension BackupService {
    static func replaceDatabase(with document: LedgerBackupDocument, context: ModelContext) throws {
        try deleteAll(context)

        var books: [UUID: LedgerBook] = [:]
        for item in document.books {
            let value = LedgerBook(id: item.id, name: item.name, sortOrder: item.sortOrder,
                                   createdAt: item.createdAt, updatedAt: item.updatedAt)
            context.insert(value); books[item.id] = value
        }
        var accounts: [UUID: Account] = [:]
        for item in document.accounts {
            guard let type = AccountType(rawValue: item.type) else {
                throw BackupServiceError.brokenReference("账户 \(item.name) 的类型无效")
            }
            let value = Account(id: item.id, name: item.name, type: type, note: item.note,
                                book: item.bookID.flatMap { books[$0] },
                                isHidden: item.isHidden, isArchived: item.isArchived ?? false,
                                sortOrder: item.sortOrder, createdAt: item.createdAt, updatedAt: item.updatedAt)
            context.insert(value); accounts[item.id] = value
        }

        var wallets: [UUID: CurrencyWallet] = [:]
        for item in document.wallets {
            guard let currency = SupportedCurrency(rawValue: item.currencyCode) else {
                throw BackupServiceError.invalidCurrency(item.currencyCode)
            }
            let value = CurrencyWallet(id: item.id, currency: currency, balance: item.balance,
                                       isEnabled: item.isEnabled, account: item.accountID.flatMap { accounts[$0] },
                                       createdAt: item.createdAt, updatedAt: item.updatedAt)
            context.insert(value); wallets[item.id] = value
        }

        var categories: [UUID: LedgerCategory] = [:]
        for item in document.categories {
            guard let type = CategoryKind(rawValue: item.type) else {
                throw BackupServiceError.brokenReference("分类 \(item.name) 的类型无效")
            }
            let value = LedgerCategory(id: item.id, name: item.name, type: type, symbolName: item.symbolName,
                                       sortOrder: item.sortOrder, isSystem: item.isSystem, bookID: item.bookID,
                                       parentID: item.parentID, isArchived: item.isArchived ?? false,
                                       createdAt: item.createdAt ?? document.exportedAt,
                                       updatedAt: item.updatedAt ?? document.exportedAt)
            context.insert(value); categories[item.id] = value
        }

        var transactions: [UUID: LedgerTransaction] = [:]
        for item in document.transactions {
            guard let type = TransactionKind(rawValue: item.type) else {
                throw BackupServiceError.brokenReference("流水 \(item.id) 的类型无效")
            }
            let parts = (item.paymentParts ?? []).map {
                TransactionPaymentPart(id: $0.id, amount: $0.amount, sortOrder: $0.sortOrder,
                                       wallet: $0.walletID.flatMap { wallets[$0] }, createdAt: $0.createdAt)
            }
            let value = LedgerTransaction(
                id: item.id, type: type, amount: item.amount, currencyCode: item.currencyCode,
                date: item.date, note: item.note,
                sourceAccount: item.sourceAccountID.flatMap { accounts[$0] }
                    ?? item.sourceWalletID.flatMap { wallets[$0]?.account },
                sourceWallet: item.sourceWalletID.flatMap { wallets[$0] },
                destinationAccount: item.destinationAccountID.flatMap { accounts[$0] }
                    ?? item.destinationWalletID.flatMap { wallets[$0]?.account },
                destinationWallet: item.destinationWalletID.flatMap { wallets[$0] },
                sourceAmount: item.sourceAmount, sourceCurrencyCode: item.sourceCurrencyCode,
                destinationAmount: item.destinationAmount, destinationCurrencyCode: item.destinationCurrencyCode,
                feeAmount: item.feeAmount, feeCurrencyCode: item.feeCurrencyCode,
                feeWallet: item.feeWalletID.flatMap { wallets[$0] }, exchangeRate: item.exchangeRate,
                adjustmentDirection: item.adjustmentDirection.flatMap(AdjustmentDirection.init(rawValue:)),
                adjustmentReason: item.adjustmentReason, category: item.categoryID.flatMap { categories[$0] },
                paymentParts: parts,
                merchantOrCounterparty: item.merchantOrCounterparty, originalAmount: item.originalAmount,
                discountAmount: item.discountAmount, recognitionImportID: item.recognitionImportID,
                createdAt: item.createdAt, updatedAt: item.updatedAt
            )
            for part in parts { part.transaction = value }
            context.insert(value); transactions[item.id] = value
        }

        for item in document.relations {
            guard let kind = TransactionRelationKind(rawValue: item.kind) else {
                throw BackupServiceError.brokenReference("退款或报销关系类型无效")
            }
            context.insert(TransactionRelation(id: item.id, kind: kind,
                                               originalTransactionID: item.originalTransactionID,
                                               relatedTransactionID: item.relatedTransactionID,
                                               amount: item.amount, createdAt: item.createdAt))
        }
        for item in document.aaSplits {
            guard let mode = AASplitCalculationMode(rawValue: item.calculationMode) else {
                throw BackupServiceError.brokenReference("AA 分摊计算方式无效")
            }
            context.insert(AASplit(
                id: item.id,
                originalTransactionID: item.originalTransactionID,
                otherPeopleCount: item.otherPeopleCount,
                calculationMode: mode,
                othersOwedAmount: item.othersOwedAmount,
                note: item.note,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            ))
        }
        for item in document.aaSettlements {
            context.insert(AASettlement(
                id: item.id,
                splitID: item.splitID,
                recoveryTransactionID: item.recoveryTransactionID,
                amount: item.amount,
                createdAt: item.createdAt
            ))
        }
        for item in document.attachments {
            context.insert(TransactionAttachment(
                id: item.id, transactionID: item.transactionID, bookID: item.bookID,
                relativePath: item.relativePath, originalFilename: item.originalFilename,
                mimeType: item.mimeType, byteCount: item.data?.count ?? item.byteCount, createdAt: item.createdAt
            ))
        }
        for item in document.templates {
            guard let type = TransactionKind(rawValue: item.type) else {
                throw BackupServiceError.brokenReference("模板 \(item.name) 的交易类型无效")
            }
            context.insert(TransactionTemplate(
                id: item.id, name: item.name, bookID: item.bookID, type: type, amount: item.amount,
                sourceWalletID: item.sourceWalletID, destinationWalletID: item.destinationWalletID,
                destinationAmount: item.destinationAmount, feeAmount: item.feeAmount,
                feeWalletID: item.feeWalletID, categoryID: item.categoryID, tagIDs: [],
                paymentParts: item.paymentParts, note: item.note,
                merchantOrCounterparty: item.merchantOrCounterparty,
                adjustmentDirection: item.adjustmentDirection.flatMap(AdjustmentDirection.init(rawValue:)),
                adjustmentReason: item.adjustmentReason, isArchived: item.isArchived,
                createdAt: item.createdAt, updatedAt: item.updatedAt
            ))
        }
        for item in document.recurringSchedules {
            guard let frequency = RecurringFrequency(rawValue: item.frequency) else {
                throw BackupServiceError.brokenReference("周期规则 \(item.name) 的频率无效")
            }
            context.insert(RecurringSchedule(
                id: item.id, name: item.name, bookID: item.bookID, frequency: frequency,
                interval: item.interval, anchorDate: item.anchorDate, nextDueDate: item.nextDueDate,
                endDate: item.endDate, timeZoneIdentifier: item.timeZoneIdentifier, draftData: item.draftData,
                isPaused: item.isPaused, isArchived: item.isArchived,
                createdAt: item.createdAt, updatedAt: item.updatedAt
            ))
        }
        for item in document.recurringOccurrences {
            context.insert(RecurringOccurrence(id: item.id, generationKey: item.generationKey,
                                               scheduleID: item.scheduleID, scheduledDate: item.scheduledDate,
                                               transactionID: item.transactionID, createdAt: item.createdAt))
        }
        for item in document.installmentPlans {
            guard let kind = InstallmentKind(rawValue: item.kind) else {
                throw BackupServiceError.brokenReference("分期计划 \(item.name) 的类型无效")
            }
            context.insert(InstallmentPlan(
                id: item.id, name: item.name, bookID: item.bookID, kind: kind,
                totalPrincipal: item.totalPrincipal, totalFee: item.totalFee,
                installmentCount: item.installmentCount, nextInstallmentIndex: item.nextInstallmentIndex,
                startDate: item.startDate, nextDueDate: item.nextDueDate, sourceWalletID: item.sourceWalletID,
                destinationWalletID: item.destinationWalletID, categoryID: item.categoryID,
                sourceTransactionID: item.sourceTransactionID, merchantOrCounterparty: item.merchantOrCounterparty,
                note: item.note, fractionDigits: item.fractionDigits, isPaused: item.isPaused,
                isArchived: item.isArchived, completedAt: item.completedAt,
                createdAt: item.createdAt, updatedAt: item.updatedAt
            ))
        }
        for item in document.installmentOccurrences {
            context.insert(InstallmentOccurrence(
                id: item.id, generationKey: item.generationKey, planID: item.planID,
                installmentIndex: item.installmentIndex, scheduledDate: item.scheduledDate,
                principalAmount: item.principalAmount, feeAmount: item.feeAmount,
                transactionID: item.transactionID, createdAt: item.createdAt
            ))
        }
        for item in document.recognitionRecords {
            guard let status = RecognitionImportStatus(rawValue: item.status),
                  let reason = RecognitionDecisionReason(rawValue: item.decisionReason),
                  let type = RecognizedTransactionType(rawValue: item.candidateType) else {
                throw BackupServiceError.brokenReference("识别记录 \(item.id) 的状态无效")
            }
            context.insert(RecognitionImportRecord(
                id: item.id, createdAt: item.createdAt, status: status, decisionReason: reason,
                candidateType: type, bookID: item.bookID, paidAmount: item.paidAmount,
                currencyCode: item.currencyCode, occurredAt: item.occurredAt,
                merchantOrCounterparty: item.merchantOrCounterparty, note: item.note,
                originalAmount: item.originalAmount, discountAmount: item.discountAmount,
                feeAmount: item.feeAmount, sourceAccountHint: item.sourceAccountHint,
                categoryCandidate: item.categoryCandidate, selectedWalletID: item.selectedWalletID,
                selectedCategoryID: item.selectedCategoryID,
                transactionFingerprint: item.transactionFingerprint, transactionID: item.transactionID
            ))
        }
        for item in document.exchangeRates {
            guard let source = ExchangeRateSource(rawValue: item.source) else {
                throw BackupServiceError.brokenReference("汇率 \(item.currencyCode) 的来源无效")
            }
            context.insert(ExchangeRate(id: item.id, currencyCode: item.currencyCode,
                                        baseCurrencyCode: item.baseCurrencyCode, rate: item.rate,
                                        source: source, updatedAt: item.updatedAt))
        }
        for item in document.budgets {
            let period = item.period.flatMap(BudgetPeriod.init(rawValue:)) ?? .monthly
            let scopeKey = item.scopeKey ?? "legacy:\(item.id.uuidString.lowercased())"
            context.insert(MonthlyBudget(id: item.id, scopeKey: scopeKey, bookID: item.bookID,
                                         monthStart: item.monthStart, currencyCode: item.currencyCode,
                                         amount: item.amount, period: period, categoryID: item.categoryID,
                                         createdAt: item.createdAt, updatedAt: item.updatedAt))
        }
        var goals: [UUID: SavingsGoal] = [:]
        for item in document.savingsGoals {
            guard let status = SavingsGoalStatus(rawValue: item.status) else {
                throw BackupServiceError.brokenReference("存钱目标 \(item.name) 的状态无效")
            }
            let value = SavingsGoal(id: item.id, bookID: item.bookID, name: item.name,
                                    targetAmount: item.targetAmount, currencyCode: item.currencyCode,
                                    targetDate: item.targetDate, symbolName: item.symbolName,
                                    colorHex: item.colorHex, status: status,
                                    createdAt: item.createdAt, updatedAt: item.updatedAt)
            context.insert(value); goals[item.id] = value
        }
        for item in document.savingsAllocations {
            context.insert(SavingsAllocation(id: item.id, amount: item.amount, date: item.date,
                                             note: item.note, sourceAccountID: item.sourceAccountID,
                                             goal: item.goalID.flatMap { goals[$0] }, createdAt: item.createdAt))
        }
        for item in document.importBatches {
            guard let preset = TransactionImportPreset(rawValue: item.preset) else {
                throw BackupServiceError.brokenReference("导入批次 \(item.id) 的预设无效")
            }
            context.insert(TransactionImportBatch(
                id: item.id, sourceName: item.sourceName, preset: preset, bookID: item.bookID,
                rowCount: item.rowCount, importedCount: item.importedCount,
                skippedCount: item.skippedCount, errorCount: item.errorCount,
                createdAt: item.createdAt, completedAt: item.completedAt, undoneAt: item.undoneAt
            ))
        }
        for item in document.importFingerprints {
            context.insert(TransactionImportFingerprint(id: item.id, value: item.value,
                                                        batchID: item.batchID, transactionID: item.transactionID,
                                                        createdAt: item.createdAt))
        }
        try context.save()
    }

    static func deleteAll(_ context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<TransactionImportFingerprint>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TransactionImportBatch>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<SavingsAllocation>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<SavingsGoal>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<RecurringOccurrence>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<InstallmentOccurrence>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<RecurringSchedule>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<InstallmentPlan>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TransactionAttachment>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TransactionRelation>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<AASettlement>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<AASplit>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TransactionTemplate>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<RecognitionImportRecord>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TransactionPaymentPart>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<LedgerTransaction>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TransactionTag>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<MonthlyBudget>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<CurrencyWallet>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Account>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<LedgerBook>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<ExchangeRate>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<LedgerCategory>()) { context.delete(item) }
    }
}
