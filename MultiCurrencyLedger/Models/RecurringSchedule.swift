import Foundation
import SwiftData

enum RecurringFrequency: String, CaseIterable, Codable, Identifiable {
    case daily, weekly, monthly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: AppLocalization.string( "天")
        case .weekly: AppLocalization.string( "周")
        case .monthly: AppLocalization.string( "月")
        case .yearly: AppLocalization.string( "年")
        }
    }
}

@Model
final class RecurringSchedule {
    @Attribute(.unique) var id: UUID
    var name: String
    var bookID: UUID
    var frequencyRawValue: String
    var interval: Int
    var anchorDate: Date
    var nextDueDate: Date
    var endDate: Date?
    var timeZoneIdentifier: String
    var draftData: Data
    var isPaused: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        bookID: UUID,
        frequency: RecurringFrequency,
        interval: Int,
        anchorDate: Date,
        nextDueDate: Date? = nil,
        endDate: Date? = nil,
        timeZoneIdentifier: String,
        draftData: Data,
        isPaused: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.bookID = bookID
        frequencyRawValue = frequency.rawValue
        self.interval = interval
        self.anchorDate = anchorDate
        self.nextDueDate = nextDueDate ?? anchorDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.draftData = draftData
        self.isPaused = isPaused
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var frequency: RecurringFrequency {
        RecurringFrequency(rawValue: frequencyRawValue) ?? .monthly
    }
}

@Model
final class RecurringOccurrence {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var generationKey: String
    var scheduleID: UUID
    var scheduledDate: Date
    var transactionID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        generationKey: String,
        scheduleID: UUID,
        scheduledDate: Date,
        transactionID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.generationKey = generationKey
        self.scheduleID = scheduleID
        self.scheduledDate = scheduledDate
        self.transactionID = transactionID
        self.createdAt = createdAt
    }
}
