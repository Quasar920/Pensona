import Foundation
import XCTest
@testable import MultiCurrencyLedger

final class LocalizationCoverageTests: XCTestCase {
    private let languages = ["zh-Hans", "zh-Hant", "en", "ja"]
    private let criticalKeys = [
        "appearance.system", "appearance.light", "appearance.dark",
        "amount.expenseRed", "amount.expenseGreen",
        "language.system", "language.zhHans", "language.zhHant", "language.en", "language.ja",
        "settings.appearance.section", "settings.appearance.displayMode", "settings.haptics",
        "settings.amountConvention", "settings.language", "settings.experience.title",
        "settings.quickLaunch.section", "settings.quickLaunch.title", "settings.quickLaunch.footer",
        "tab.ledger", "tab.assets", "tab.plans", "tab.reports",
        "preview.language", "preview.appearance", "preview.amountColors",
        "preview.simplifiedGlass", "preview.summary", "preview.primaryAction",
        "上一个月", "下一个月", "选择年月，当前%@", "搜索当前月", "关闭搜索",
        "这个月还没有记录", "未来的收支记录会显示在这里",
        "还没有记账记录", "点击下方 + 开始添加第一笔交易",
        "总资产", "报销", "借入", "借出",
        "设置", "数据导入与导出", "账单导入", "备份与导出",
        "安全与隐私", "密码、解锁与隐私遮罩",
        "外观与金额颜色", "显示、触觉与金额颜色",
        "币种与汇率", "本位币与汇率管理",
        "数据恢复与迁移", "备份恢复、迁移快照与清除",
        "语言", "App 显示语言", "关于与帮助", "关于 App 与数据说明",
        "流水", "资产", "计划", "统计", "支出", "收入", "转账", "换汇", "调整",
        "保存", "取消", "操作失败", "未知错误", "餐饮支出", "工资收入"
    ]

    func testDynamicStringsFollowTheInAppLanguagePreference() {
        let defaults = UserDefaults.standard
        let languageKey = "appLanguage"
        let previous = defaults.object(forKey: languageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: languageKey)
            } else {
                defaults.removeObject(forKey: languageKey)
            }
        }

        defaults.set(AppLanguage.english.rawValue, forKey: languageKey)
        XCTAssertEqual(AppLocalization.locale.identifier, "en")
        XCTAssertEqual(AssetModuleKind.reimbursement.title, "Reimbursement")

        defaults.set(AppLanguage.japanese.rawValue, forKey: languageKey)
        XCTAssertEqual(AssetModuleKind.reimbursement.title, "立替精算")

        defaults.set(AppLanguage.traditionalChinese.rawValue, forKey: languageKey)
        XCTAssertEqual(AssetModuleKind.reimbursement.title, "報銷")
    }

    func testCriticalKeysExistAndAreNonEmptyInAllLanguages() throws {
        let strings = try catalogStrings()
        for key in criticalKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "Missing key: \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for language in languages {
                let localization = try XCTUnwrap(
                    localizations[language] as? [String: Any],
                    "Missing \(language) for \(key)"
                )
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                let value = try XCTUnwrap(unit["value"] as? String)
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    func testEveryCatalogEntryIsTranslatedInAllSupportedLanguages() throws {
        let strings = try catalogStrings()
        XCTAssertGreaterThan(strings.count, 700, "The catalog unexpectedly lost full-app coverage")

        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], "Invalid entry: \(key)")
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                "Missing localizations for \(key)"
            )
            for language in languages {
                let value = try localizedValue(language, localizations: localizations)
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Missing \(language) translation for \(key)"
                )
            }
        }
    }

    func testFormatArgumentsMatchAcrossLanguages() throws {
        let strings = try catalogStrings()
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let formats = try languages.map { language -> [String] in
                let localization = try XCTUnwrap(localizations[language] as? [String: Any])
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                return formatArguments(in: try XCTUnwrap(unit["value"] as? String))
            }
            XCTAssertTrue(formats.dropFirst().allSatisfy { $0 == formats[0] }, "Format mismatch: \(key)")
        }
    }

    func testEnglishUserFacingCopyDoesNotContainChineseFallback() throws {
        let strings = try catalogStrings()
        let han = try NSRegularExpression(pattern: "\\p{Han}", options: [])

        for (key, rawEntry) in strings where containsHan(key, regex: han) {
            let entry = try XCTUnwrap(rawEntry as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let english = try localizedValue("en", localizations: localizations)
            XCTAssertFalse(
                containsHan(english, regex: han),
                "English still contains Chinese fallback for \(key): \(english)"
            )
        }
    }

    func testEnglishSettingsCopyDoesNotFallBackToChineseSourceText() throws {
        let strings = try catalogStrings()
        let settingsKeys = [
            "设置", "数据导入与导出", "安全与隐私", "外观与金额颜色",
            "币种与汇率", "数据恢复与迁移", "语言", "关于与帮助"
        ]
        for key in settingsKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let english = try localizedValue("en", localizations: localizations)
            let source = try localizedValue("zh-Hans", localizations: localizations)
            XCTAssertNotEqual(english, source, "English falls back to source for \(key)")
        }
    }

    private func catalogStrings() throws -> [String: Any] {
        let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testsURL.deletingLastPathComponent()
            .appendingPathComponent("MultiCurrencyLedger/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(object?["strings"] as? [String: Any])
    }

    private func formatArguments(in value: String) -> [String] {
        let regex = try! NSRegularExpression(
            pattern: "%([0-9]+\\$)?(?:hh|h|ll|l)?[@dfiu]",
            options: []
        )
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range)
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            .map { $0.replacingOccurrences(of: #"^%[0-9]+\$"#, with: "%", options: .regularExpression) }
            .sorted()
    }

    private func containsHan(_ value: String, regex: NSRegularExpression) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private func localizedValue(_ language: String, localizations: [String: Any]) throws -> String {
        let localization = try XCTUnwrap(localizations[language] as? [String: Any])
        let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }
}
