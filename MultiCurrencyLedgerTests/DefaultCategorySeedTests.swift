import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class DefaultCategorySeedTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(LedgerSchemaV3.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testApprovedCatalogHasStableUniqueIdentifiersAndCompleteShape() {
        XCTAssertEqual(DefaultCategoryCatalog.expenseRoots.count, 20)
        XCTAssertEqual(DefaultCategoryCatalog.incomeRoots.count, 12)
        XCTAssertEqual(DefaultCategoryCatalog.expense.count, 114)
        XCTAssertEqual(DefaultCategoryCatalog.income.count, 46)
        XCTAssertEqual(Set(DefaultCategoryCatalog.all.map(\.id)).count, 160)
        XCTAssertEqual(Set(DefaultCategoryCatalog.all.map(\.localizationKey)).count, 160)
        for descriptor in DefaultCategoryCatalog.all {
            XCTAssertFalse(descriptor.names.value(for: Locale(identifier: "zh-Hans")).isEmpty)
            XCTAssertFalse(descriptor.names.value(for: Locale(identifier: "zh-Hant")).isEmpty)
            XCTAssertFalse(descriptor.names.value(for: Locale(identifier: "en")).isEmpty)
            XCTAssertFalse(descriptor.names.value(for: Locale(identifier: "ja")).isEmpty)
        }
    }

    func testFreshSeedCreatesCompleteTwoLevelCatalogAndIsIdempotent() throws {
        try InitialDataService.seedIfNeeded(context: context)
        var categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        XCTAssertEqual(categories.count, 160)
        XCTAssertEqual(categories.count { $0.type == .expense && $0.parentID == nil }, 20)
        XCTAssertEqual(categories.count { $0.type == .income && $0.parentID == nil }, 12)
        XCTAssertTrue(categories.allSatisfy { $0.bookID == nil })

        try InitialDataService.seedIfNeeded(context: context)
        categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        XCTAssertEqual(categories.count, 160)
    }

    func testIntentionalPostUpgradeDeletionIsNotReseeded() throws {
        try InitialDataService.seedIfNeeded(context: context)
        let category = try XCTUnwrap(
            context.fetch(FetchDescriptor<LedgerCategory>()).first {
                $0.systemLocalizationKey == "category.expense.delivery.fee"
            }
        )
        context.delete(category)
        try context.save()

        try InitialDataService.seedIfNeeded(context: context)

        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        XCTAssertEqual(categories.count, 159)
        XCTAssertFalse(categories.contains { $0.systemLocalizationKey == "category.expense.delivery.fee" })
    }

    func testLegacySystemRowsUpgradeInPlaceWhileCustomAndCompatibilityRowsSurvive() throws {
        let legacyFood = LedgerCategory(
            name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0, isSystem: true
        )
        let unknownLegacy = LedgerCategory(
            name: "旧版神秘分类", type: .expense, symbolName: "questionmark", sortOrder: 99, isSystem: true
        )
        let custom = LedgerCategory(
            name: "我的分类", type: .expense, symbolName: "star", sortOrder: 1, isSystem: false
        )
        let transaction = LedgerTransaction(type: .expense, bookID: UUID(), category: legacyFood)
        context.insert(legacyFood)
        context.insert(unknownLegacy)
        context.insert(custom)
        context.insert(transaction)
        try context.save()

        try DefaultCategoryCatalog.upgrade(context: context)

        XCTAssertEqual(transaction.category?.id, legacyFood.id)
        XCTAssertEqual(legacyFood.systemLocalizationKey, "category.expense.food")
        XCTAssertTrue(unknownLegacy.isCompatibilityItem)
        XCTAssertFalse(custom.isSystem)
        XCTAssertEqual(custom.name, "我的分类")
        let roots = try context.fetch(FetchDescriptor<LedgerCategory>()).filter {
            $0.type == .expense && $0.parentID == nil
        }
        XCTAssertGreaterThanOrEqual(custom.sortOrder, 20)
        XCTAssertTrue(roots.contains { $0.id == custom.id })
    }

    func testCanonicalLegacyNameWinsBeforeBroaderAlias() throws {
        let canonicalShopping = LedgerCategory(
            name: "购物", type: .expense, symbolName: "bag", sortOrder: 2, isSystem: true
        )
        let legacyDaily = LedgerCategory(
            name: "日用", type: .expense, symbolName: "cart", sortOrder: 4, isSystem: true
        )
        context.insert(canonicalShopping)
        context.insert(legacyDaily)
        try context.save()

        try DefaultCategoryCatalog.upgrade(context: context)

        XCTAssertEqual(canonicalShopping.systemLocalizationKey, "category.expense.shopping")
        XCTAssertTrue(legacyDaily.isCompatibilityItem)
        let shoppingDefaults = try context.fetch(FetchDescriptor<LedgerCategory>()).filter {
            $0.systemLocalizationKey == "category.expense.shopping"
        }
        XCTAssertEqual(shoppingDefaults.count, 1)
    }
}
