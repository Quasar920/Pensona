import Foundation
import Observation
import SwiftUI

private final class AppLocalizationBundleToken: NSObject {}

enum AppLocalization {
    private static let languageKey = "appLanguage"

    private static var resourceBundle: Bundle {
        let candidates = [Bundle.main, Bundle(for: AppLocalizationBundleToken.self)]
            + Bundle.allBundles
            + Bundle.allFrameworks
        return candidates.first {
            $0.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: "en"
            ) != nil
        } ?? .main
    }

    static var locale: Locale {
        #if DEBUG
        if let previewLanguage = ProcessInfo.processInfo.environment["APP_PREVIEW_LANGUAGE"] {
            return Locale(identifier: previewLanguage)
        }
        #endif
        guard let rawValue = UserDefaults.standard.string(forKey: languageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .autoupdatingCurrent
        }
        return language.locale
    }

    @_semantics("string.init_localized")
    static func string(_ resource: String.LocalizationValue) -> String {
        let locale = locale
        let bundle = resourceBundle
        let localization = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: [locale.identifier]
        ).first
        let localizedBundle = localization
            .flatMap { bundle.path(forResource: $0, ofType: "lproj") }
            .flatMap(Bundle.init(path:))
            ?? bundle
        return String(localized: resource, bundle: localizedBundle, locale: locale)
    }
}

/// The first release is intentionally light-only. Keeping this as a persisted
/// value lets a later dark-mode release add a migration without exposing an
/// unavailable appearance choice today.
enum AppAppearance: String, CaseIterable, Identifiable {
    case light

    var id: String { rawValue }
    var title: String {
        AppLocalization.string("appearance.light")
    }

    var colorScheme: ColorScheme? {
        .light
    }
}

enum AmountColorConvention: String, CaseIterable, Identifiable {
    case expenseRedIncomeGreen
    case expenseGreenIncomeRed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .expenseRedIncomeGreen: AppLocalization.string("amount.expenseRed")
        case .expenseGreenIncomeRed: AppLocalization.string("amount.expenseGreen")
        }
    }

    static func regionalDefault(regionCode: String?) -> Self {
        let redIncomeRegions: Set<String> = ["CN", "HK", "MO", "TW"]
        return redIncomeRegions.contains(regionCode?.uppercased() ?? "")
            ? .expenseGreenIncomeRed
            : .expenseRedIncomeGreen
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, simplifiedChinese, traditionalChinese, english, japanese

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: AppLocalization.string("language.system")
        case .simplifiedChinese: AppLocalization.string("language.zhHans")
        case .traditionalChinese: AppLocalization.string("language.zhHant")
        case .english: AppLocalization.string("language.en")
        case .japanese: AppLocalization.string("language.ja")
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .traditionalChinese: Locale(identifier: "zh-Hant")
        case .english: Locale(identifier: "en")
        case .japanese: Locale(identifier: "ja")
        }
    }
}

@MainActor
@Observable
final class AppPreferences {
    static let appearanceKey = "appearanceMode"
    static let hapticsKey = "hapticsEnabled"
    static let amountColorKey = "amountColorConvention"
    static let languageKey = "appLanguage"
    static let autoExpandCategoryOnNewEntryKey = "autoExpandCategoryOnNewEntry"

    private let defaults: UserDefaults

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Self.hapticsKey) }
    }
    var amountColorConvention: AmountColorConvention {
        didSet { defaults.set(amountColorConvention.rawValue, forKey: Self.amountColorKey) }
    }
    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.languageKey) }
    }

    init(
        defaults: UserDefaults = .standard,
        regionCode: String? = Locale.current.region?.identifier
    ) {
        self.defaults = defaults
        // Existing system and dark-mode settings are deliberately migrated to
        // the sole supported appearance instead of following the device.
        appearance = .light
        defaults.set(AppAppearance.light.rawValue, forKey: Self.appearanceKey)
        hapticsEnabled = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        amountColorConvention = AmountColorConvention(
            rawValue: defaults.string(forKey: Self.amountColorKey) ?? ""
        ) ?? .regionalDefault(regionCode: regionCode)
        language = AppLanguage(
            rawValue: defaults.string(forKey: Self.languageKey) ?? ""
        ) ?? .system
    }

    var locale: Locale { language.locale }
}
