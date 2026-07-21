import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class CategoryHierarchyServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: CategoryService!
    private var book: LedgerBook!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(LedgerSchemaV3.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        service = CategoryService(context: context, iconStore: CategoryIconStore(rootURL: temporaryDirectory()))
        book = LedgerBook(name: "日常")
        context.insert(book)
        try context.save()
    }

    func testCreateMovePromoteAndDepthRules() throws {
        let food = try service.create(name: "餐饮", type: .expense, symbolName: "fork.knife", bookID: book.id)
        let travel = try service.create(name: "旅行", type: .expense, symbolName: "airplane", bookID: book.id)
        let breakfast = try service.create(name: "早餐", type: .expense, symbolName: "sunrise", bookID: book.id, parent: food)

        XCTAssertThrowsError(try service.create(
            name: "豆浆", type: .expense, symbolName: "cup.and.saucer", bookID: book.id, parent: breakfast
        )) { XCTAssertEqual($0 as? CategoryError, .invalidParent) }

        try service.moveChild(breakfast, to: travel)
        XCTAssertEqual(breakfast.parentID, travel.id)
        try service.promoteToRoot(breakfast)
        XCTAssertNil(breakfast.parentID)
        try service.convertRootToChild(breakfast, under: food)
        XCTAssertEqual(breakfast.parentID, food.id)
    }

    func testRootWithChildrenCannotBecomeChildAndCyclesAreRejected() throws {
        let food = try service.create(name: "餐饮", type: .expense, symbolName: "fork.knife", bookID: book.id)
        let travel = try service.create(name: "旅行", type: .expense, symbolName: "airplane", bookID: book.id)
        _ = try service.create(name: "早餐", type: .expense, symbolName: "sunrise", bookID: book.id, parent: food)

        XCTAssertThrowsError(try service.convertRootToChild(food, under: travel)) {
            XCTAssertEqual($0 as? CategoryError, .childrenRequireMigration(1))
        }
        XCTAssertThrowsError(try service.moveChild(travel, to: travel))
    }

    func testSameLevelBatchReorderIsAtomic() throws {
        let first = try service.create(name: "一", type: .income, symbolName: "1.circle", bookID: book.id)
        let second = try service.create(name: "二", type: .income, symbolName: "2.circle", bookID: book.id)
        let third = try service.create(name: "三", type: .income, symbolName: "3.circle", bookID: book.id)
        try service.reorder([third, first, second])
        XCTAssertEqual([third.sortOrder, first.sortOrder, second.sortOrder], [0, 1, 2])

        let child = try service.create(name: "子", type: .income, symbolName: "circle", bookID: book.id, parent: first)
        XCTAssertThrowsError(try service.reorder([first, child])) {
            XCTAssertEqual($0 as? CategoryError, .invalidReorder)
        }
        XCTAssertEqual(first.sortOrder, 1)
    }

    func testReorderModeMovesOneItemWithoutDroppingAnySibling() throws {
        let first = try service.create(name: "一", type: .expense, symbolName: "1.circle", bookID: book.id)
        let second = try service.create(name: "二", type: .expense, symbolName: "2.circle", bookID: book.id)
        let third = try service.create(name: "三", type: .expense, symbolName: "3.circle", bookID: book.id)
        let reordered = CategoryReorderMode.moving(
            sourceID: third.id,
            before: first.id,
            in: [first, second, third]
        )
        XCTAssertEqual(reordered.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(Set(reordered.map(\.id)).count, 3)
    }

    func testDeleteRequiresMigrationAndMovesExactReferencesAndChildren() throws {
        let source = try service.create(name: "旧分类", type: .expense, symbolName: "archivebox", bookID: book.id)
        let target = try service.create(name: "新分类", type: .expense, symbolName: "tray", bookID: book.id)
        let child = try service.create(name: "旧子类", type: .expense, symbolName: "tag", bookID: book.id, parent: source)
        let direct = LedgerTransaction(type: .expense, bookID: book.id, category: source)
        let descendant = LedgerTransaction(type: .expense, bookID: book.id, category: child)
        context.insert(direct)
        context.insert(descendant)
        try context.save()

        let summary = try service.usageSummary(for: source)
        XCTAssertEqual(summary, CategoryUsageSummary(
            directTransactionCount: 1,
            descendantTransactionCount: 1,
            directChildCount: 1
        ))
        XCTAssertThrowsError(try service.delete(source)) {
            XCTAssertEqual($0 as? CategoryError, .childrenRequireMigration(1))
        }

        try service.delete(source, migratingReferencesTo: target)
        XCTAssertEqual(direct.category?.id, target.id)
        XCTAssertEqual(descendant.category?.id, child.id)
        XCTAssertEqual(child.parentID, target.id)
        XCTAssertFalse(try context.fetch(FetchDescriptor<LedgerCategory>()).contains { $0.id == source.id })
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
