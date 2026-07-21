import Foundation
import SwiftData

enum CategoryIconSource: String, Codable, CaseIterable, Sendable {
    case builtIn
    case userUploaded
}

@Model
final class LedgerCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRawValue: String
    var symbolName: String
    var sortOrder: Int
    var isSystem: Bool
    var bookID: UUID?
    var parentID: UUID?
    var isArchived: Bool = false
    var systemLocalizationKey: String?
    var iconSourceRawValue: String = CategoryIconSource.builtIn.rawValue
    var placeholderResourceName: String?
    var userIconRelativePath: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        type: CategoryKind,
        symbolName: String,
        sortOrder: Int,
        isSystem: Bool = false,
        bookID: UUID? = nil,
        parentID: UUID? = nil,
        isArchived: Bool = false,
        systemLocalizationKey: String? = nil,
        iconSource: CategoryIconSource = .builtIn,
        placeholderResourceName: String? = nil,
        userIconRelativePath: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        typeRawValue = type.rawValue
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.isSystem = isSystem
        self.bookID = bookID
        self.parentID = parentID
        self.isArchived = isArchived
        self.systemLocalizationKey = systemLocalizationKey
        iconSourceRawValue = iconSource.rawValue
        self.placeholderResourceName = placeholderResourceName
        self.userIconRelativePath = userIconRelativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: CategoryKind { CategoryKind(rawValue: typeRawValue) ?? .expense }
    var iconSource: CategoryIconSource {
        get { CategoryIconSource(rawValue: iconSourceRawValue) ?? .builtIn }
        set { iconSourceRawValue = newValue.rawValue }
    }
    var isCompatibilityItem: Bool {
        systemLocalizationKey?.hasPrefix("category.compatibility.") == true
    }

    func localizedName(locale: Locale = .current, bundle: Bundle = .main) -> String {
        guard isSystem, let systemLocalizationKey, !systemLocalizationKey.isEmpty else {
            return name
        }
        if let catalogName = DefaultCategoryCatalog.localizedName(
            for: systemLocalizationKey,
            locale: locale
        ) {
            return catalogName
        }
        let identifiers = [locale.identifier, locale.language.languageCode?.identifier]
            .compactMap { $0 }
        let localizedBundle = identifiers.lazy.compactMap { identifier -> Bundle? in
            bundle.path(forResource: identifier, ofType: "lproj").flatMap(Bundle.init(path:))
        }.first
        return (localizedBundle ?? bundle).localizedString(
            forKey: systemLocalizationKey,
            value: name,
            table: nil
        )
    }
}
