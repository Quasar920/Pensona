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
        XCTAssertEqual(DefaultCategoryCatalog.expenseRoots.count, 16)
        XCTAssertEqual(DefaultCategoryCatalog.incomeRoots.count, 3)
        XCTAssertEqual(DefaultCategoryCatalog.expense.count, 64)
        XCTAssertEqual(DefaultCategoryCatalog.income.count, 12)
        XCTAssertEqual(Set(DefaultCategoryCatalog.all.map(\.id)).count, 76)
        XCTAssertEqual(Set(DefaultCategoryCatalog.all.map(\.localizationKey)).count, 76)
        for descriptor in DefaultCategoryCatalog.all {
            XCTAssertFalse(descriptor.names.value(for: Locale(identifier: "zh-Hans")).isEmpty)
            XCTAssertFalse(descriptor.names.value(for: Locale(identifier: "zh-Hant")).isEmpty)
            XCTAssertFalse(descriptor.names.value(for: Locale(identifier: "en")).isEmpty)
            XCTAssertFalse(descriptor.names.value(for: Locale(identifier: "ja")).isEmpty)
        }
    }

    func testExpenseCatalogMatchesApprovedReferenceHierarchy() {
        let expectedRoots = [
            "餐饮", "咖啡", "外卖", "购物", "交通", "网约车", "消遣", "固定支出",
            "投资", "运动", "服务", "成长", "健康", "人情", "居住", "兜底"
        ]
        let expectedChildren: [String: [String]] = [
            "餐饮": ["正餐", "奶茶", "水果", "茶", "餐饮兜底"],
            "咖啡": [],
            "外卖": [],
            "购物": ["网购", "购物（超市）", "零食", "购物兜底"],
            "交通": ["公交", "地铁", "高铁", "飞机", "共享车"],
            "网约车": [],
            "消遣": ["盲盒", "氪金", "彩票", "电影", "演唱会", "消遣兜底"],
            "固定支出": ["订阅", "生活耗品", "话费", "VPN", "管理费用", "快递", "固定支出兜底"],
            "投资": ["保险", "流出", "投资兜底"],
            "运动": ["游泳", "运动兜底"],
            "服务": ["理发店", "按摩", "服务兜底"],
            "成长": ["资料", "考试费", "成长兜底"],
            "健康": ["药店", "医院", "健康兜底"],
            "人情": ["礼金", "礼物", "借出", "人情兜底"],
            "居住": ["房租", "水电费", "居住兜底"],
            "兜底": []
        ]

        XCTAssertEqual(DefaultCategoryCatalog.expenseRoots.map(\.fallbackName), expectedRoots)
        for root in DefaultCategoryCatalog.expenseRoots {
            let children = DefaultCategoryCatalog.expense
                .filter { $0.parentIdentifier == root.id }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.fallbackName)
            XCTAssertEqual(children, expectedChildren[root.fallbackName])
        }
    }

    func testIncomeCatalogMatchesApprovedReferenceHierarchy() {
        let expectedRoots = ["主动收入-工资", "被动收入", "其他收入"]
        let expectedChildren: [String: [String]] = [
            "主动收入-工资": ["工资", "副业收入", "主动收入兜底"],
            "被动收入": ["投资", "变现", "被动收入兜底"],
            "其他收入": ["彩票", "红包", "其他收入兜底"]
        ]

        XCTAssertEqual(DefaultCategoryCatalog.incomeRoots.map(\.fallbackName), expectedRoots)
        for root in DefaultCategoryCatalog.incomeRoots {
            let children = DefaultCategoryCatalog.income
                .filter { $0.parentIdentifier == root.id }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.fallbackName)
            XCTAssertEqual(children, expectedChildren[root.fallbackName])
        }
    }

    func testFreshSeedCreatesCompleteTwoLevelCatalogAndIsIdempotent() throws {
        try InitialDataService.seedIfNeeded(context: context)
        var categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        XCTAssertEqual(categories.count, 76)
        XCTAssertEqual(categories.count { $0.type == .expense && $0.parentID == nil }, 16)
        XCTAssertEqual(categories.count { $0.type == .income && $0.parentID == nil }, 3)
        XCTAssertTrue(categories.allSatisfy { $0.bookID == nil })

        try InitialDataService.seedIfNeeded(context: context)
        categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        XCTAssertEqual(categories.count, 76)
    }

    func testIntentionalPostUpgradeDeletionIsNotReseeded() throws {
        try InitialDataService.seedIfNeeded(context: context)
        let category = try XCTUnwrap(
            context.fetch(FetchDescriptor<LedgerCategory>()).first {
                $0.systemLocalizationKey == "category.expense.food.fallback"
            }
        )
        context.delete(category)
        try context.save()

        try InitialDataService.seedIfNeeded(context: context)

        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        XCTAssertEqual(categories.count, 75)
        XCTAssertFalse(categories.contains { $0.systemLocalizationKey == "category.expense.food.fallback" })
    }

    func testObsoleteSystemIncomeOtherIsDeletedButUserCategoryIsPreserved() throws {
        try InitialDataService.seedIfNeeded(context: context)
        let obsolete = LedgerCategory(
            name: "其他",
            type: .income,
            symbolName: "ellipsis.circle",
            sortOrder: 99,
            isSystem: true,
            systemLocalizationKey: "category.compatibility.obsolete-income-other"
        )
        let obsoleteChild = LedgerCategory(
            name: "旧其他子分类",
            type: .income,
            symbolName: "ellipsis.circle",
            sortOrder: 0,
            isSystem: true,
            parentID: obsolete.id,
            systemLocalizationKey: "category.compatibility.obsolete-income-other.child"
        )
        let custom = LedgerCategory(
            name: "其他",
            type: .income,
            symbolName: "star",
            sortOrder: 100,
            isSystem: false
        )
        context.insert(obsolete)
        context.insert(obsoleteChild)
        context.insert(custom)
        try context.save()

        try InitialDataService.seedIfNeeded(context: context)

        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        XCTAssertFalse(categories.contains { $0.id == obsolete.id })
        XCTAssertFalse(categories.contains { $0.id == obsoleteChild.id })
        XCTAssertTrue(categories.contains { $0.id == custom.id })
        XCTAssertTrue(categories.contains {
            $0.systemLocalizationKey == "category.income.other"
                && $0.localizedName(locale: Locale(identifier: "zh-Hans")) == "其他收入"
        })
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
        XCTAssertGreaterThanOrEqual(custom.sortOrder, 16)
        XCTAssertTrue(roots.contains { $0.id == custom.id })
    }

    func testPreviousExpenseTreeMigratesInPlaceAndArchivesRetiredRows() throws {
        let oldDrinks = LedgerCategory(
            name: "咖啡茶饮", type: .expense, symbolName: "cup.and.saucer", sortOrder: 1,
            isSystem: true, systemLocalizationKey: "category.expense.drinks"
        )
        let oldMilkTea = LedgerCategory(
            name: "奶茶", type: .expense, symbolName: "cup.and.saucer", sortOrder: 2,
            isSystem: true, parentID: oldDrinks.id,
            systemLocalizationKey: "category.expense.drinks.milktea"
        )
        let retiredCoffeeChild = LedgerCategory(
            name: "咖啡", type: .expense, symbolName: "cup.and.saucer", sortOrder: 0,
            isSystem: true, parentID: oldDrinks.id,
            systemLocalizationKey: "category.expense.drinks.coffee"
        )
        let oldUtilities = LedgerCategory(
            name: "水电通讯", type: .expense, symbolName: "bolt.house", sortOrder: 7,
            isSystem: true, systemLocalizationKey: "category.expense.utilities"
        )
        let transaction = LedgerTransaction(type: .expense, bookID: UUID(), category: oldMilkTea)
        [oldDrinks, oldMilkTea, retiredCoffeeChild, oldUtilities].forEach(context.insert)
        context.insert(transaction)
        try context.save()

        try DefaultCategoryCatalog.upgrade(context: context)

        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let food = try XCTUnwrap(categories.first { $0.systemLocalizationKey == "category.expense.food" })
        let housing = try XCTUnwrap(categories.first { $0.systemLocalizationKey == "category.expense.housing" })
        XCTAssertEqual(oldDrinks.systemLocalizationKey, "category.expense.coffee")
        XCTAssertNil(oldDrinks.parentID)
        XCTAssertEqual(oldMilkTea.systemLocalizationKey, "category.expense.food.milk-tea")
        XCTAssertEqual(oldMilkTea.parentID, food.id)
        XCTAssertEqual(transaction.category?.id, oldMilkTea.id)
        XCTAssertEqual(oldUtilities.systemLocalizationKey, "category.expense.housing.utilities")
        XCTAssertEqual(oldUtilities.parentID, housing.id)
        XCTAssertTrue(retiredCoffeeChild.isArchived)
        XCTAssertTrue(retiredCoffeeChild.isCompatibilityItem)
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
