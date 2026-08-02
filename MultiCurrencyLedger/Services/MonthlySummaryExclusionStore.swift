import Foundation

struct MonthlySummaryExclusion: Codable, Equatable {
    var income = false
    var expense = false
}

enum MonthlySummaryExclusionStore {
    private static let storageKey = "monthlySummaryExclusionsByTransactionID"

    static func exclusion(for transactionID: UUID) -> MonthlySummaryExclusion {
        entries()[transactionID.uuidString] ?? MonthlySummaryExclusion()
    }

    static func set(_ exclusion: MonthlySummaryExclusion, for transactionID: UUID) {
        var values = entries()
        if exclusion.income || exclusion.expense {
            values[transactionID.uuidString] = exclusion
        } else {
            values.removeValue(forKey: transactionID.uuidString)
        }
        save(values)
    }

    static func remove(transactionIDs: some Sequence<UUID>) {
        var values = entries()
        for id in transactionIDs {
            values.removeValue(forKey: id.uuidString)
        }
        save(values)
    }

    private static func entries() -> [String: MonthlySummaryExclusion] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: MonthlySummaryExclusion].self, from: data)) ?? [:]
    }

    private static func save(_ values: [String: MonthlySummaryExclusion]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(values), forKey: storageKey)
    }
}
