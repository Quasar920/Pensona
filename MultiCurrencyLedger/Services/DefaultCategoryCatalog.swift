import Foundation
import SwiftData

struct DefaultCategoryDescriptor: Identifiable, Hashable, Sendable {
    struct Names: Hashable, Sendable {
        let zhHans: String
        let zhHant: String
        let en: String
        let ja: String

        func value(for locale: Locale) -> String {
            let identifier = locale.identifier.lowercased()
            if identifier.hasPrefix("zh-hant") || identifier.contains("-tw") || identifier.contains("-hk") {
                return zhHant
            }
            if identifier.hasPrefix("en") { return en }
            if identifier.hasPrefix("ja") { return ja }
            return zhHans
        }
    }

    let id: String
    let localizationKey: String
    let names: Names
    let type: CategoryKind
    let symbolName: String
    let parentIdentifier: String?
    let sortOrder: Int

    var fallbackName: String { names.zhHans }
}

enum DefaultCategoryCatalog {
    private struct RawRoot {
        let id: String
        let names: DefaultCategoryDescriptor.Names
        let symbol: String
        let children: [(String, DefaultCategoryDescriptor.Names)]
    }

    static let expense: [DefaultCategoryDescriptor] = descriptors(for: .expense, roots: expenseRaw)
    static let income: [DefaultCategoryDescriptor] = descriptors(for: .income, roots: incomeRaw)
    static let all = expense + income
    static let expenseRoots = expense.filter { $0.parentIdentifier == nil }
    static let incomeRoots = income.filter { $0.parentIdentifier == nil }

    static func descriptor(localizationKey: String) -> DefaultCategoryDescriptor? {
        all.first { $0.localizationKey == localizationKey }
    }

    static func localizedName(for localizationKey: String, locale: Locale) -> String? {
        descriptor(localizationKey: localizationKey)?.names.value(for: locale)
    }

    /// Upgrades legacy seeds in place so transaction relationships keep pointing
    /// to the same model objects, then fills only missing approved defaults.
    @MainActor
    static func upgrade(context: ModelContext) throws {
        var categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        // One successfully committed catalog key is the durable in-store version
        // marker. The seed transaction is atomic, so this also distinguishes an
        // intentional later deletion from an incomplete legacy upgrade.
        if categories.contains(where: {
            guard let key = $0.systemLocalizationKey else { return false }
            return descriptor(localizationKey: key) != nil
        }) {
            normalizeCustomOrdering(categories)
            try context.save()
            return
        }
        var claimedCategoryIDs = Set<UUID>()

        // Resolve the whole catalog in priority order so a broad legacy alias
        // (for example “日用” → shopping) can never steal the canonical “购物” row.
        for descriptor in all {
            guard let category = bestLegacyMatch(
                for: descriptor,
                categories: categories,
                excluding: claimedCategoryIDs
            ) else { continue }
            apply(descriptor, to: category)
            claimedCategoryIDs.insert(category.id)
        }
        for category in categories where category.isSystem && !claimedCategoryIDs.contains(category.id) {
            if category.systemLocalizationKey == nil
                || descriptor(localizationKey: category.systemLocalizationKey ?? "") == nil {
                category.systemLocalizationKey = "category.compatibility.\(category.id.uuidString.lowercased())"
                category.bookID = nil
                category.updatedAt = .now
            }
        }

        var byIdentifier: [String: LedgerCategory] = [:]
        for descriptor in all where descriptor.parentIdentifier == nil {
            let category = category(for: descriptor, in: categories) ?? insert(descriptor, parentID: nil, context: context)
            apply(descriptor, to: category)
            byIdentifier[descriptor.id] = category
            if !categories.contains(where: { $0.id == category.id }) { categories.append(category) }
        }
        for descriptor in all where descriptor.parentIdentifier != nil {
            guard let parentIdentifier = descriptor.parentIdentifier,
                  let parent = byIdentifier[parentIdentifier] else { continue }
            let category = category(for: descriptor, in: categories)
                ?? insert(descriptor, parentID: parent.id, context: context)
            apply(descriptor, to: category, parentID: parent.id)
            byIdentifier[descriptor.id] = category
            if !categories.contains(where: { $0.id == category.id }) { categories.append(category) }
        }

        normalizeCustomOrdering(categories)
        try context.save()
    }

    private static func category(
        for descriptor: DefaultCategoryDescriptor,
        in categories: [LedgerCategory]
    ) -> LedgerCategory? {
        categories.first { $0.systemLocalizationKey == descriptor.localizationKey }
    }

    @MainActor
    private static func insert(
        _ descriptor: DefaultCategoryDescriptor,
        parentID: UUID?,
        context: ModelContext
    ) -> LedgerCategory {
        let category = LedgerCategory(
            name: descriptor.fallbackName,
            type: descriptor.type,
            symbolName: descriptor.symbolName,
            sortOrder: descriptor.sortOrder,
            isSystem: true,
            parentID: parentID,
            systemLocalizationKey: descriptor.localizationKey,
            placeholderResourceName: descriptor.symbolName
        )
        context.insert(category)
        return category
    }

    private static func apply(
        _ descriptor: DefaultCategoryDescriptor,
        to category: LedgerCategory,
        parentID: UUID? = nil
    ) {
        category.name = descriptor.fallbackName
        category.typeRawValue = descriptor.type.rawValue
        category.symbolName = descriptor.symbolName
        category.sortOrder = descriptor.sortOrder
        category.isSystem = true
        category.bookID = nil
        category.parentID = parentID
        category.isArchived = false
        category.systemLocalizationKey = descriptor.localizationKey
        category.iconSource = .builtIn
        category.placeholderResourceName = descriptor.symbolName
        category.updatedAt = .now
    }

    private static func bestLegacyMatch(
        for descriptor: DefaultCategoryDescriptor,
        categories: [LedgerCategory],
        excluding claimedCategoryIDs: Set<UUID>
    ) -> LedgerCategory? {
        let available = categories.filter {
            $0.isSystem && $0.type == descriptor.type && !claimedCategoryIDs.contains($0.id)
        }
        if let exactKey = available.first(where: { $0.systemLocalizationKey == descriptor.localizationKey }) {
            return exactKey
        }
        guard descriptor.parentIdentifier == nil else { return nil }
        let canonicalNames = [
            descriptor.names.zhHans, descriptor.names.zhHant,
            descriptor.names.en, descriptor.names.ja
        ]
        if let exactName = available.first(where: {
            canonicalNames.contains($0.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }) {
            return exactName
        }
        let aliases: [String: String] = [
            "日用": "expense.shopping", "医疗": "expense.healthcare",
            "学习": "expense.education", "人情": "expense.social",
            "工资": "income.salary", "兼职": "income.sidejob"
        ]
        return available.first {
            aliases[$0.name.trimmingCharacters(in: .whitespacesAndNewlines)] == descriptor.id
        }
    }

    private static func normalizeCustomOrdering(_ categories: [LedgerCategory]) {
        for type in [CategoryKind.expense, .income] {
            let roots = categories.filter { $0.type == type && $0.parentID == nil }
            let systemCount = (type == .expense ? expenseRoots : incomeRoots).count
            for (offset, category) in roots.filter({ !$0.isSystem || $0.isCompatibilityItem }).sorted(by: stableSort).enumerated() {
                category.sortOrder = systemCount + offset
            }
            for parent in roots {
                let children = categories.filter { $0.parentID == parent.id }
                let defaultCount = all.filter { $0.parentIdentifier == identifier(for: parent) }.count
                for (offset, category) in children.filter({ !$0.isSystem || $0.isCompatibilityItem }).sorted(by: stableSort).enumerated() {
                    category.sortOrder = defaultCount + offset
                }
            }
        }
    }

    private static func identifier(for category: LedgerCategory) -> String? {
        guard let key = category.systemLocalizationKey else { return nil }
        return descriptor(localizationKey: key)?.id
    }

    private static func stableSort(_ lhs: LedgerCategory, _ rhs: LedgerCategory) -> Bool {
        lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
    }

    private static func descriptors(
        for type: CategoryKind,
        roots: [RawRoot]
    ) -> [DefaultCategoryDescriptor] {
        roots.enumerated().flatMap { rootIndex, raw in
            let root = DefaultCategoryDescriptor(
                id: raw.id,
                localizationKey: "category.\(raw.id)",
                names: raw.names,
                type: type,
                symbolName: raw.symbol,
                parentIdentifier: nil,
                sortOrder: rootIndex
            )
            let children = raw.children.enumerated().map { childIndex, child in
                DefaultCategoryDescriptor(
                    id: "\(raw.id).\(child.0)",
                    localizationKey: "category.\(raw.id).\(child.0)",
                    names: child.1,
                    type: type,
                    symbolName: raw.symbol,
                    parentIdentifier: raw.id,
                    sortOrder: childIndex
                )
            }
            return [root] + children
        }
    }

    private static func n(_ zhHans: String, _ zhHant: String, _ en: String, _ ja: String) -> DefaultCategoryDescriptor.Names {
        .init(zhHans: zhHans, zhHant: zhHant, en: en, ja: ja)
    }

    private static let expenseRaw: [RawRoot] = [
        .init(id: "expense.food", names: n("餐饮", "餐飲", "Dining", "食事"), symbol: "fork.knife", children: [
            ("breakfast", n("早餐", "早餐", "Breakfast", "朝食")), ("meal", n("正餐", "正餐", "Meals", "食事")),
            ("fastfood", n("快餐", "速食", "Fast food", "ファストフード")), ("snack", n("零食", "零食", "Snacks", "おやつ")),
            ("latenight", n("夜宵", "宵夜", "Late-night food", "夜食"))]),
        .init(id: "expense.drinks", names: n("咖啡茶饮", "咖啡茶飲", "Coffee & Tea", "コーヒー・お茶"), symbol: "cup.and.saucer", children: [
            ("coffee", n("咖啡", "咖啡", "Coffee", "コーヒー")), ("tea", n("茶饮", "茶飲", "Tea", "お茶")),
            ("milktea", n("奶茶", "奶茶", "Milk tea", "ミルクティー")), ("alcohol", n("酒水", "酒水", "Alcohol", "お酒"))]),
        .init(id: "expense.delivery", names: n("外卖", "外賣", "Delivery", "デリバリー"), symbol: "takeoutbag.and.cup.and.straw", children: [
            ("meal", n("餐食外卖", "餐食外賣", "Meal delivery", "食事配達")), ("grocery", n("生鲜配送", "生鮮配送", "Grocery delivery", "生鮮配達")),
            ("errand", n("跑腿", "跑腿", "Errands", "代行")), ("fee", n("配送费", "配送費", "Delivery fee", "配送料"))]),
        .init(id: "expense.shopping", names: n("购物", "購物", "Shopping", "買い物"), symbol: "bag", children: [
            ("daily", n("日用品", "日用品", "Daily essentials", "日用品")), ("clothing", n("服饰", "服飾", "Clothing", "衣類")),
            ("beauty", n("美妆", "美妝", "Beauty", "美容")), ("digital", n("数码", "數碼", "Electronics", "デジタル機器")),
            ("home", n("家居用品", "家居用品", "Home goods", "家庭用品"))]),
        .init(id: "expense.transport", names: n("交通", "交通", "Transport", "交通"), symbol: "tram", children: [
            ("bus", n("公交", "公車", "Bus", "バス")), ("metro", n("地铁", "地鐵", "Metro", "地下鉄")),
            ("train", n("火车", "火車", "Train", "電車")), ("flight", n("飞机", "飛機", "Flight", "飛行機")),
            ("ship", n("船舶", "船舶", "Ferry", "船"))]),
        .init(id: "expense.ridehail", names: n("网约车", "網約車", "Ride Hailing", "配車"), symbol: "car.side", children: [
            ("taxi", n("打车", "叫車", "Taxi", "タクシー")), ("carpool", n("拼车", "共乘", "Carpool", "相乗り")),
            ("driver", n("代驾", "代駕", "Designated driver", "運転代行")), ("rental", n("租车", "租車", "Car rental", "レンタカー"))]),
        .init(id: "expense.housing", names: n("居住", "居住", "Housing", "住居"), symbol: "house", children: [
            ("rent", n("房租", "房租", "Rent", "家賃")), ("mortgage", n("房贷", "房貸", "Mortgage", "住宅ローン")),
            ("property", n("物业", "物業", "Property fees", "管理費")), ("renovation", n("装修", "裝修", "Renovation", "リフォーム")),
            ("insurance", n("住房保险", "住房保險", "Home insurance", "住宅保険"))]),
        .init(id: "expense.utilities", names: n("水电通讯", "水電通訊", "Utilities & Telecom", "水道光熱・通信"), symbol: "bolt.house", children: [
            ("water", n("水费", "水費", "Water", "水道")), ("electricity", n("电费", "電費", "Electricity", "電気")),
            ("gas", n("燃气", "燃氣", "Gas", "ガス")), ("mobile", n("手机", "手機", "Mobile", "携帯電話")),
            ("internet", n("宽带", "寬頻", "Internet", "インターネット"))]),
        .init(id: "expense.fixed", names: n("固定支出", "固定支出", "Fixed Expenses", "固定費"), symbol: "calendar.badge.clock", children: [
            ("membership", n("会员订阅", "會員訂閱", "Memberships", "会員契約")), ("software", n("软件服务", "軟體服務", "Software", "ソフトウェア")),
            ("insurance", n("保险", "保險", "Insurance", "保険")), ("parking", n("车位", "車位", "Parking space", "駐車場")),
            ("payment", n("固定缴费", "固定繳費", "Recurring bills", "定期支払"))]),
        .init(id: "expense.healthcare", names: n("医疗健康", "醫療健康", "Healthcare", "医療・健康"), symbol: "cross.case", children: [
            ("clinic", n("门诊", "門診", "Clinic", "外来診療")), ("medicine", n("药品", "藥品", "Medicine", "薬")),
            ("checkup", n("体检", "體檢", "Checkup", "健康診断")), ("dental", n("牙科", "牙科", "Dental", "歯科")),
            ("mental", n("心理健康", "心理健康", "Mental health", "メンタルヘルス"))]),
        .init(id: "expense.fitness", names: n("运动健身", "運動健身", "Fitness", "運動・フィットネス"), symbol: "figure.run", children: [
            ("gym", n("健身房", "健身房", "Gym", "ジム")), ("gear", n("运动装备", "運動裝備", "Sports gear", "スポーツ用品")),
            ("ball", n("球类", "球類", "Ball sports", "球技")), ("outdoor", n("户外", "戶外", "Outdoors", "アウトドア")),
            ("event", n("赛事", "賽事", "Sporting events", "大会"))]),
        .init(id: "expense.entertainment", names: n("娱乐", "娛樂", "Entertainment", "娯楽"), symbol: "gamecontroller", children: [
            ("movie", n("电影", "電影", "Movies", "映画")), ("game", n("游戏", "遊戲", "Games", "ゲーム")),
            ("show", n("演出", "演出", "Shows", "公演")), ("ktv", n("KTV", "KTV", "Karaoke", "カラオケ")),
            ("content", n("内容订阅", "內容訂閱", "Content subscriptions", "コンテンツ購読"))]),
        .init(id: "expense.travel", names: n("旅行", "旅行", "Travel", "旅行"), symbol: "airplane", children: [
            ("hotel", n("住宿", "住宿", "Accommodation", "宿泊")), ("ticket", n("门票", "門票", "Admission", "入場券")),
            ("local", n("当地交通", "當地交通", "Local transport", "現地交通")), ("visa", n("签证", "簽證", "Visa", "ビザ")),
            ("shopping", n("旅行购物", "旅行購物", "Travel shopping", "旅行中の買い物"))]),
        .init(id: "expense.education", names: n("教育成长", "教育成長", "Learning", "教育・成長"), symbol: "book", children: [
            ("course", n("课程", "課程", "Courses", "講座")), ("books", n("书籍", "書籍", "Books", "書籍")),
            ("exam", n("考试", "考試", "Exams", "試験")), ("training", n("培训", "培訓", "Training", "研修")),
            ("stationery", n("文具", "文具", "Stationery", "文房具"))]),
        .init(id: "expense.social", names: n("人情往来", "人情往來", "Social Gifts", "交際"), symbol: "gift", children: [
            ("cashgift", n("礼金", "禮金", "Cash gifts", "祝儀")), ("gift", n("礼物", "禮物", "Gifts", "贈り物")),
            ("treat", n("请客", "請客", "Treating others", "おごり")), ("donation", n("捐赠", "捐贈", "Donations", "寄付")),
            ("parents", n("孝亲", "孝親", "Family support", "親孝行"))]),
        .init(id: "expense.family", names: n("家庭", "家庭", "Family", "家族"), symbol: "figure.2.and.child.holdinghands", children: [
            ("childcare", n("育儿", "育兒", "Childcare", "育児")), ("supplies", n("家庭用品", "家庭用品", "Household supplies", "家庭用品")),
            ("housekeeping", n("家政", "家政", "Housekeeping", "家事代行")), ("repair", n("维修", "維修", "Repairs", "修理")),
            ("elder", n("长辈支出", "長輩支出", "Elder support", "高齢家族支援"))]),
        .init(id: "expense.pets", names: n("宠物", "寵物", "Pets", "ペット"), symbol: "pawprint", children: [
            ("food", n("食品", "食品", "Food", "フード")), ("medical", n("医疗", "醫療", "Veterinary", "医療")),
            ("grooming", n("美容", "美容", "Grooming", "トリミング")), ("supplies", n("用品", "用品", "Supplies", "用品")),
            ("boarding", n("寄养", "寄養", "Boarding", "ペットホテル"))]),
        .init(id: "expense.services", names: n("服务", "服務", "Services", "サービス"), symbol: "wrench.and.screwdriver", children: [
            ("delivery", n("快递", "快遞", "Courier", "宅配")), ("laundry", n("洗衣", "洗衣", "Laundry", "クリーニング")),
            ("hair", n("理发", "理髮", "Haircut", "理髪")), ("legal", n("法律服务", "法律服務", "Legal services", "法律サービス")),
            ("professional", n("专业服务", "專業服務", "Professional services", "専門サービス"))]),
        .init(id: "expense.taxes", names: n("税费", "稅費", "Taxes & Fees", "税金・手数料"), symbol: "doc.text", children: [
            ("tax", n("税款", "稅款", "Taxes", "税金")), ("fee", n("手续费", "手續費", "Fees", "手数料")),
            ("fine", n("罚款", "罰款", "Fines", "罰金")), ("government", n("政务费用", "政務費用", "Government fees", "行政手数料")),
            ("customs", n("关税", "關稅", "Customs duty", "関税"))]),
        .init(id: "expense.other", names: n("其他", "其他", "Other", "その他"), symbol: "ellipsis.circle", children: [
            ("temporary", n("临时支出", "臨時支出", "Temporary expense", "一時的な支出")),
            ("uncategorized", n("未归类", "未分類", "Uncategorized", "未分類"))])
    ]

    private static let incomeRaw: [RawRoot] = [
        .init(id: "income.salary", names: n("工资薪酬", "工資薪酬", "Salary", "給与"), symbol: "banknote", children: [
            ("base", n("基本工资", "基本工資", "Base salary", "基本給")), ("allowance", n("津贴", "津貼", "Allowance", "手当")),
            ("overtime", n("加班费", "加班費", "Overtime", "残業代")), ("commission", n("佣金", "佣金", "Commission", "歩合給"))]),
        .init(id: "income.bonus", names: n("奖金", "獎金", "Bonus", "賞与"), symbol: "trophy", children: [
            ("performance", n("绩效奖", "績效獎", "Performance bonus", "業績賞与")), ("annual", n("年终奖", "年終獎", "Year-end bonus", "年末賞与")),
            ("project", n("项目奖金", "專案獎金", "Project bonus", "プロジェクト賞与"))]),
        .init(id: "income.sidejob", names: n("兼职副业", "兼職副業", "Side Work", "副業"), symbol: "briefcase", children: [
            ("freelance", n("自由职业", "自由職業", "Freelance", "フリーランス")), ("content", n("内容收入", "內容收入", "Content income", "コンテンツ収入")),
            ("temporary", n("临时工作", "臨時工作", "Temporary work", "臨時仕事"))]),
        .init(id: "income.business", names: n("经营收入", "經營收入", "Business Income", "事業収入"), symbol: "storefront", children: [
            ("goods", n("商品销售", "商品銷售", "Product sales", "商品販売")), ("service", n("服务收入", "服務收入", "Service income", "サービス収入")),
            ("platform", n("平台结算", "平台結算", "Platform payout", "プラットフォーム精算"))]),
        .init(id: "income.investment", names: n("投资收益", "投資收益", "Investment Returns", "投資収益"), symbol: "chart.line.uptrend.xyaxis", children: [
            ("dividend", n("股息", "股息", "Dividends", "配当")), ("fund", n("基金收益", "基金收益", "Fund returns", "ファンド収益")),
            ("securities", n("证券收益", "證券收益", "Securities gains", "証券収益")), ("other", n("其他投资", "其他投資", "Other investments", "その他の投資"))]),
        .init(id: "income.interest", names: n("利息", "利息", "Interest", "利息"), symbol: "percent", children: [
            ("deposit", n("存款利息", "存款利息", "Deposit interest", "預金利息")), ("bond", n("债券利息", "債券利息", "Bond interest", "債券利息"))]),
        .init(id: "income.rent", names: n("租金", "租金", "Rental Income", "賃貸収入"), symbol: "house.and.flag", children: [
            ("home", n("房屋租金", "房屋租金", "Property rent", "住宅賃料")), ("parking", n("车位租金", "車位租金", "Parking rent", "駐車場賃料")),
            ("equipment", n("设备租金", "設備租金", "Equipment rent", "設備賃料"))]),
        .init(id: "income.refund", names: n("退款", "退款", "Refunds", "返金"), symbol: "arrow.uturn.backward.circle", children: [
            ("shopping", n("购物退款", "購物退款", "Shopping refund", "購入返金")), ("service", n("服务退款", "服務退款", "Service refund", "サービス返金")),
            ("deposit", n("押金退回", "押金退回", "Deposit returned", "保証金返還"))]),
        .init(id: "income.reimbursement", names: n("报销到账", "報銷入帳", "Reimbursement", "経費精算"), symbol: "doc.text.magnifyingglass", children: [
            ("company", n("公司报销", "公司報銷", "Company reimbursement", "会社経費精算")),
            ("insurance", n("保险理赔", "保險理賠", "Insurance claim", "保険金"))]),
        .init(id: "income.gift", names: n("礼金", "禮金", "Gifts", "贈与"), symbol: "gift", children: [
            ("redpacket", n("红包", "紅包", "Red packet", "お年玉")), ("cashgift", n("礼金", "禮金", "Cash gift", "祝儀")),
            ("present", n("赠与", "贈與", "Gift", "贈与"))]),
        .init(id: "income.resale", names: n("出售闲置", "出售閒置", "Resale", "不用品販売"), symbol: "shippingbox", children: [
            ("secondhand", n("二手交易", "二手交易", "Secondhand sale", "中古品販売")), ("asset", n("资产出售", "資產出售", "Asset sale", "資産売却"))]),
        .init(id: "income.other", names: n("其他收入", "其他收入", "Other Income", "その他の収入"), symbol: "ellipsis.circle", children: [
            ("temporary", n("临时收入", "臨時收入", "Temporary income", "一時収入")),
            ("uncategorized", n("未归类", "未分類", "Uncategorized", "未分類"))])
    ]
}
