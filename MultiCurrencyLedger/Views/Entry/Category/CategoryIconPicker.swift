import PhotosUI
import SwiftUI

struct CategoryIconDraft: Equatable {
    var symbolName: String
    var uploadedData: Data?
    var renderingMode: CategoryIconRenderingMode
    var keepsExistingUpload: Bool = false
}

struct CategoryIconPicker: View {
    @Binding var draft: CategoryIconDraft
    @State private var selectedPhoto: PhotosPickerItem?

    private let symbols = [
        "tag", "star", "heart", "fork.knife", "cup.and.saucer", "takeoutbag.and.cup.and.straw",
        "bag", "tram", "car.side", "house", "bolt.house", "calendar.badge.clock",
        "cross.case", "figure.run", "gamecontroller", "airplane", "book", "gift",
        "pawprint", "wrench.and.screwdriver", "doc.text", "banknote", "trophy",
        "briefcase", "storefront", "chart.line.uptrend.xyaxis", "percent", "shippingbox"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("图标").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            draft.symbolName = symbol
                            draft.uploadedData = nil
                            draft.keepsExistingUpload = false
                        } label: {
                            Image(systemName: symbol)
                                .frame(width: 44, height: 44)
                                .foregroundStyle(draft.uploadedData == nil && draft.symbolName == symbol ? .blue : .primary)
                                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(draft.uploadedData == nil && draft.symbolName == symbol ? .blue : .clear)
                                }
                        }
                        .buttonStyle(LedgerGlassPressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(draft.uploadedData == nil ? "上传图标" : "更换图片", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
                if draft.uploadedData != nil {
                    Picker("图片样式", selection: $draft.renderingMode) {
                        Text("保留原图").tag(CategoryIconRenderingMode.original)
                        Text("单色化").tag(CategoryIconRenderingMode.monochrome)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            draft.uploadedData = try? await selectedPhoto.loadTransferable(type: Data.self)
            draft.keepsExistingUpload = false
        }
    }
}

struct CategoryIconImage: View {
    let category: LedgerCategory
    let size: CGFloat
    @State private var uploadedImage: UIImage?

    var body: some View {
        Group {
            if let uploadedImage {
                Image(uiImage: uploadedImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else {
                DefaultCategoryIcon(category: category, size: size)
            }
        }
        .frame(width: size, height: size)
        .saturation(0)
        .contrast(1.05)
        .task(id: category.userIconRelativePath) {
            guard category.iconSource == .userUploaded,
                  let path = category.userIconRelativePath else {
                uploadedImage = nil
                return
            }
            uploadedImage = try? CategoryIconStore().thumbnail(relativePath: path)
        }
    }
}

/// A fixed square canvas keeps built-in category artwork visually consistent even
/// when a category name would otherwise suggest icons with very different shapes.
private struct DefaultCategoryIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let category: LedgerCategory
    let size: CGFloat

    private var symbolName: String {
        Self.symbols[category.systemLocalizationKey ?? ""] ?? category.symbolName
    }

    private var artwork: CategoryLineArtwork.Kind? {
        CategoryLineArtwork.Kind(localizationKey: category.systemLocalizationKey)
    }

    var body: some View {
        Group {
            if let assetName = Self.assetNames[category.systemLocalizationKey ?? ""],
               let image = CategoryDarkIconRenderer.image(
                   named: assetName,
                   usesDarkLinework: colorScheme == .dark
               ) {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    // A few source illustrations have more transparent
                    // padding than the rest. Normalize their visible size
                    // without changing the shared tile layout.
                    .frame(width: size * assetScale, height: size * assetScale)
                    .frame(width: size, height: size)
            } else if let artwork {
                CategoryLineArtwork(kind: artwork, size: size)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.53, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(colorScheme == .dark ? EntryCategoryAppearance.darkInk : .black.opacity(0.86))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    private var assetScale: CGFloat {
        Self.assetScales[category.systemLocalizationKey ?? ""] ?? 1
    }

    private static let assetScales: [String: CGFloat] = [
        "category.expense.delivery": 1.58,
        "category.expense.transport": 1.38,
        "category.expense.ridehail": 1.16,
        "category.expense.entertainment": 1.38,
        "category.expense.health": 1.22,
        "category.expense.fallback": 1.28
    ]

    private static let symbols: [String: String] = [
        "category.expense.food": "fork.knife",
        "category.expense.food.meal": "fork.knife",
        "category.expense.food.milk-tea": "cup.and.saucer",
        "category.expense.food.fruit": "apple.logo",
        "category.expense.food.tea": "teapot",
        "category.expense.food.fallback": "ellipsis.circle",
        "category.expense.coffee": "cup.and.saucer",
        "category.expense.delivery": "takeoutbag.and.cup.and.straw",
        "category.expense.shopping": "bag",
        "category.expense.shopping.online": "cart",
        "category.expense.shopping.supermarket": "basket",
        "category.expense.shopping.snacks": "popcorn",
        "category.expense.shopping.fallback": "ellipsis.circle",
        "category.expense.transport": "tram",
        "category.expense.transport.bus": "bus",
        "category.expense.transport.metro": "tram",
        "category.expense.transport.high-speed-rail": "train.side.front.car",
        "category.expense.transport.flight": "airplane",
        "category.expense.transport.bike-sharing": "bicycle",
        "category.expense.ridehail": "car.side",
        "category.expense.entertainment": "gamecontroller",
        "category.expense.entertainment.blind-box": "cube.box",
        "category.expense.entertainment.game-topup": "gamecontroller",
        "category.expense.entertainment.lottery": "ticket",
        "category.expense.entertainment.movie": "film",
        "category.expense.entertainment.concert": "music.mic",
        "category.expense.entertainment.fallback": "ellipsis.circle",
        "category.expense.fixed": "calendar",
        "category.expense.fixed.subscription": "rectangle.3.group",
        "category.expense.fixed.consumables": "spray.bottle",
        "category.expense.fixed.mobile": "iphone",
        "category.expense.fixed.vpn": "lock.shield",
        "category.expense.fixed.management": "building.2",
        "category.expense.fixed.courier": "shippingbox",
        "category.expense.fixed.fallback": "ellipsis.circle",
        "category.expense.investment": "chart.line.uptrend.xyaxis",
        "category.expense.investment.insurance": "shield",
        "category.expense.investment.outflow": "arrow.up.right",
        "category.expense.investment.fallback": "ellipsis.circle",
        "category.expense.sport": "figure.run",
        "category.expense.sport.swimming": "figure.pool.swim",
        "category.expense.sport.fallback": "ellipsis.circle",
        "category.expense.services": "wrench.and.screwdriver",
        "category.expense.services.hair-salon": "scissors",
        "category.expense.services.massage": "hand.raised",
        "category.expense.services.fallback": "ellipsis.circle",
        "category.expense.growth": "lightbulb",
        "category.expense.growth.materials": "doc.text",
        "category.expense.growth.exam": "pencil.and.list.clipboard",
        "category.expense.growth.fallback": "ellipsis.circle",
        "category.expense.health": "heart.text.square",
        "category.expense.health.pharmacy": "cross.case",
        "category.expense.health.hospital": "cross",
        "category.expense.health.fallback": "ellipsis.circle",
        "category.expense.social": "gift",
        "category.expense.social.cashgift": "banknote",
        "category.expense.social.gift": "gift",
        "category.expense.social.lending": "person.2",
        "category.expense.social.fallback": "ellipsis.circle",
        "category.expense.housing": "house",
        "category.expense.housing.rent": "house",
        "category.expense.housing.utilities": "bolt.house",
        "category.expense.housing.fallback": "ellipsis.circle",
        "category.expense.fallback": "square.grid.2x2",
        "category.income.salary": "envelope.open",
        "category.income.salary.salary": "banknote",
        "category.income.salary.side-income": "person.crop.rectangle",
        "category.income.salary.fallback": "square.grid.2x2",
        "category.income.investment": "chart.line.uptrend.xyaxis",
        "category.income.investment.investment": "bird",
        "category.income.investment.monetization": "arrow.triangle.2.circlepath",
        "category.income.investment.fallback": "square.grid.2x2",
        "category.income.other": "ellipsis.circle",
        "category.income.other.lottery": "ticket",
        "category.income.other.red-packet": "envelope",
        "category.income.other.fallback": "square.grid.2x2"
    ]

    // First-pass artwork mapping from the supplied English-named icon archive.
    // Unmatched categories intentionally continue using the existing built-in artwork.
    private static let assetNames: [String: String] = [
        "category.expense.food": "expense-dining",
        "category.expense.food.meal": "expense-subcategory-food-meal",
        "category.expense.food.milk-tea": "expense-subcategory-food-milk-tea",
        "category.expense.food.fruit": "expense-subcategory-food-fruit",
        "category.expense.food.tea": "expense-subcategory-food-tea",
        "category.expense.food.fallback": "expense-subcategory-catch-all",
        "category.expense.coffee": "expense-coffee",
        "category.expense.delivery": "expense-delivery",
        "category.expense.shopping": "expense-shopping",
        "category.expense.shopping.online": "expense-subcategory-shopping-online",
        "category.expense.shopping.supermarket": "expense-subcategory-shopping-supermarket",
        "category.expense.shopping.snacks": "expense-subcategory-shopping-snacks",
        "category.expense.shopping.fallback": "expense-subcategory-catch-all",
        "category.expense.transport": "expense-transport",
        "category.expense.transport.bus": "expense-subcategory-transport-bus",
        "category.expense.transport.metro": "expense-subcategory-transport-metro",
        "category.expense.transport.high-speed-rail": "expense-subcategory-transport-high-speed-rail",
        "category.expense.transport.flight": "expense-subcategory-transport-flight",
        "category.expense.transport.bike-sharing": "expense-subcategory-transport-bike-sharing",
        "category.expense.ridehail": "expense-ride-hailing",
        "category.expense.entertainment": "expense-leisure",
        "category.expense.entertainment.blind-box": "expense-subcategory-entertainment-blind-box",
        "category.expense.entertainment.game-topup": "expense-subcategory-entertainment-game-topup",
        "category.expense.entertainment.lottery": "expense-subcategory-entertainment-lottery",
        "category.expense.entertainment.movie": "expense-subcategory-entertainment-movie",
        "category.expense.entertainment.concert": "expense-subcategory-entertainment-concert",
        "category.expense.entertainment.fallback": "expense-subcategory-catch-all",
        "category.expense.fixed.subscription": "expense-subcategory-fixed-subscription",
        "category.expense.fixed.consumables": "expense-subcategory-fixed-consumables",
        "category.expense.fixed.mobile": "expense-subcategory-fixed-mobile",
        "category.expense.fixed.vpn": "expense-subcategory-fixed-vpn",
        "category.expense.fixed.management": "expense-subcategory-fixed-management",
        "category.expense.fixed.courier": "expense-subcategory-fixed-courier",
        "category.expense.fixed.fallback": "expense-subcategory-catch-all",
        "category.expense.investment": "expense-investments",
        "category.expense.investment.insurance": "expense-subcategory-investment-insurance",
        "category.expense.investment.outflow": "expense-subcategory-investment-outflow",
        "category.expense.investment.fallback": "expense-subcategory-catch-all",
        "category.expense.sport": "expense-sports",
        "category.expense.sport.swimming": "expense-subcategory-sport-swimming",
        "category.expense.sport.fallback": "expense-subcategory-catch-all",
        "category.expense.services": "expense-services",
        "category.expense.services.hair-salon": "expense-subcategory-services-hair-salon",
        "category.expense.services.massage": "expense-subcategory-services-massage",
        "category.expense.services.fallback": "expense-subcategory-catch-all",
        "category.expense.growth": "expense-growth",
        "category.expense.growth.materials": "expense-subcategory-growth-materials",
        "category.expense.growth.exam": "expense-subcategory-growth-exam",
        "category.expense.growth.fallback": "expense-subcategory-catch-all",
        "category.expense.health": "expense-health",
        "category.expense.health.pharmacy": "expense-subcategory-health-pharmacy",
        "category.expense.health.hospital": "expense-subcategory-health-hospital",
        "category.expense.health.fallback": "expense-subcategory-catch-all",
        "category.expense.social": "expense-social-gifts",
        "category.expense.social.cashgift": "expense-subcategory-social-cashgift",
        "category.expense.social.gift": "expense-subcategory-social-gift",
        "category.expense.social.lending": "expense-subcategory-social-lending",
        "category.expense.social.fallback": "expense-subcategory-catch-all",
        "category.expense.housing": "expense-housing",
        "category.expense.housing.rent": "expense-subcategory-housing-rent",
        "category.expense.housing.utilities": "expense-subcategory-housing-utilities",
        "category.expense.housing.fallback": "expense-subcategory-catch-all",
        "category.expense.fallback": "expense-catch-all",
        "category.income.salary": "income-active",
        "category.income.salary.salary": "income-subcategory-salary",
        "category.income.salary.side-income": "income-subcategory-side-income",
        "category.income.salary.fallback": "expense-subcategory-catch-all",
        "category.income.investment": "income-passive",
        "category.income.investment.investment": "income-subcategory-investment",
        "category.income.investment.monetization": "income-subcategory-monetization",
        "category.income.investment.fallback": "expense-subcategory-catch-all",
        "category.income.other": "income-other",
        "category.income.other.lottery": "expense-subcategory-entertainment-lottery",
        "category.income.other.red-packet": "income-subcategory-red-packet",
        "category.income.other.fallback": "expense-subcategory-catch-all"
    ]
}

/// Purpose-drawn line art for the categories whose meaning is too specific for
/// a generic system symbol. Every mark is drawn in the same 32-point canvas.
private struct CategoryLineArtwork: View {
    @Environment(\.colorScheme) private var colorScheme
    enum Kind {
        case milkTea, grapes, teaGlass, fixedExpenses, subscriptionButton, printerFee, toiletPaper

        init?(localizationKey: String?) {
            switch localizationKey {
            case "category.expense.food.milk-tea": self = .milkTea
            case "category.expense.food.fruit": self = .grapes
            case "category.expense.food.tea": self = .teaGlass
            case "category.expense.fixed.subscription": self = .subscriptionButton
            case "category.expense.fixed": self = .fixedExpenses
            case "category.expense.fixed.management": self = .printerFee
            case "category.expense.fixed.consumables": self = .toiletPaper
            default: return nil
            }
        }
    }

    let kind: Kind
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 32
            context.translateBy(
                x: (canvasSize.width - 32 * scale) / 2,
                y: (canvasSize.height - 32 * scale) / 2
            )
            context.scaleBy(x: scale, y: scale)
            switch kind {
            case .milkTea: drawMilkTea(in: &context)
            case .grapes: drawGrapes(in: &context)
            case .teaGlass: drawTeaGlass(in: &context)
            case .fixedExpenses: drawFixedExpenses(in: &context)
            case .subscriptionButton: drawSubscriptionButton(in: &context)
            case .printerFee: drawPrinterFee(in: &context)
            case .toiletPaper: drawToiletPaper(in: &context)
            }
        }
        .frame(width: size, height: size)
    }

    private func stroke(_ path: Path, in context: inout GraphicsContext, width: CGFloat = 1.65) {
        context.stroke(
            path,
            with: .color(iconColor),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    private var iconColor: Color {
        colorScheme == .dark ? EntryCategoryAppearance.darkInk : .black.opacity(0.88)
    }

    private func drawMilkTea(in context: inout GraphicsContext) {
        var straw = Path()
        straw.move(to: CGPoint(x: 18, y: 4))
        straw.addLine(to: CGPoint(x: 22, y: 9))
        stroke(straw, in: &context)

        var cup = Path()
        cup.move(to: CGPoint(x: 8, y: 9))
        cup.addLine(to: CGPoint(x: 24, y: 9))
        cup.addLine(to: CGPoint(x: 21.5, y: 26))
        cup.addLine(to: CGPoint(x: 10.5, y: 26))
        cup.closeSubpath()
        stroke(cup, in: &context)

        var lid = Path()
        lid.move(to: CGPoint(x: 10, y: 6.8))
        lid.addLine(to: CGPoint(x: 22, y: 6.8))
        stroke(lid, in: &context)

        for center in [CGPoint(x: 13.5, y: 18), CGPoint(x: 18, y: 18.5), CGPoint(x: 16, y: 22)] {
            stroke(Path(ellipseIn: CGRect(x: center.x - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5)), in: &context, width: 1.35)
        }
    }

    private func drawGrapes(in context: inout GraphicsContext) {
        var stem = Path()
        stem.move(to: CGPoint(x: 16, y: 5.2))
        stem.addCurve(to: CGPoint(x: 16, y: 9.4), control1: CGPoint(x: 14.3, y: 6.8), control2: CGPoint(x: 16.7, y: 8))
        stroke(stem, in: &context)

        var leaf = Path()
        leaf.move(to: CGPoint(x: 16, y: 9.5))
        leaf.addCurve(to: CGPoint(x: 22, y: 6.5), control1: CGPoint(x: 18.2, y: 6.8), control2: CGPoint(x: 20.5, y: 6.2))
        leaf.addCurve(to: CGPoint(x: 19, y: 12), control1: CGPoint(x: 22, y: 9), control2: CGPoint(x: 20.8, y: 11.4))
        leaf.addLine(to: CGPoint(x: 16, y: 9.5))
        stroke(leaf, in: &context, width: 1.55)

        for center in [
            CGPoint(x: 13, y: 12), CGPoint(x: 18.2, y: 12),
            CGPoint(x: 10.5, y: 16.5), CGPoint(x: 15.7, y: 16.5), CGPoint(x: 21, y: 16.5),
            CGPoint(x: 13, y: 21), CGPoint(x: 18.2, y: 21),
            CGPoint(x: 15.7, y: 25)
        ] {
            stroke(Path(ellipseIn: CGRect(x: center.x - 2.45, y: center.y - 2.45, width: 4.9, height: 4.9)), in: &context, width: 1.55)
        }
    }

    private func drawTeaGlass(in context: inout GraphicsContext) {
        var glass = Path()
        glass.move(to: CGPoint(x: 10, y: 7))
        glass.addLine(to: CGPoint(x: 22, y: 7))
        glass.addLine(to: CGPoint(x: 20, y: 20.5))
        glass.addCurve(to: CGPoint(x: 12, y: 20.5), control1: CGPoint(x: 18.5, y: 21.6), control2: CGPoint(x: 13.5, y: 21.6))
        glass.closeSubpath()
        stroke(glass, in: &context, width: 1.75)

        var teaLevel = Path()
        teaLevel.move(to: CGPoint(x: 11.4, y: 14.4))
        teaLevel.addCurve(to: CGPoint(x: 20.6, y: 14.4), control1: CGPoint(x: 14, y: 15.1), control2: CGPoint(x: 18, y: 15.1))
        stroke(teaLevel, in: &context, width: 1.25)

        var saucer = Path()
        saucer.move(to: CGPoint(x: 7.5, y: 23))
        saucer.addCurve(to: CGPoint(x: 24.5, y: 23), control1: CGPoint(x: 11.5, y: 27), control2: CGPoint(x: 20.5, y: 27))
        saucer.addLine(to: CGPoint(x: 7.5, y: 23))
        stroke(saucer, in: &context, width: 1.7)
    }

    private func drawSubscriptionButton(in context: inout GraphicsContext) {
        let button = Path(roundedRect: CGRect(x: 6, y: 6.5, width: 20, height: 8), cornerRadius: 4)
        stroke(button, in: &context, width: 1.8)
        let label = context.resolve(
            Text("SUBS")
                .font(.system(size: 5.1, weight: .bold, design: .rounded))
                .tracking(-0.25)
                .foregroundStyle(iconColor)
        )
        context.draw(label, at: CGPoint(x: 16, y: 10.5), anchor: .center)

        var hand = Path()
        hand.move(to: CGPoint(x: 14, y: 25))
        hand.addLine(to: CGPoint(x: 14, y: 17))
        hand.addCurve(to: CGPoint(x: 15.8, y: 17), control1: CGPoint(x: 14, y: 15.8), control2: CGPoint(x: 15.8, y: 15.8))
        hand.addLine(to: CGPoint(x: 15.8, y: 21))
        hand.addLine(to: CGPoint(x: 17, y: 19.5))
        hand.addCurve(to: CGPoint(x: 19.4, y: 21), control1: CGPoint(x: 18, y: 18.5), control2: CGPoint(x: 19.8, y: 19.6))
        hand.addLine(to: CGPoint(x: 19.4, y: 23))
        hand.addCurve(to: CGPoint(x: 17.5, y: 26), control1: CGPoint(x: 19.4, y: 24.6), control2: CGPoint(x: 18.7, y: 25.6))
        hand.addLine(to: CGPoint(x: 15.5, y: 26))
        hand.addCurve(to: CGPoint(x: 14, y: 25), control1: CGPoint(x: 14.7, y: 26), control2: CGPoint(x: 14, y: 25.6))
        stroke(hand, in: &context, width: 1.65)
    }

    private func drawFixedExpenses(in context: inout GraphicsContext) {
        let calendar = Path(roundedRect: CGRect(x: 7, y: 6.5, width: 18, height: 19), cornerRadius: 2.2)
        stroke(calendar, in: &context, width: 0.95)

        var rings = Path()
        rings.move(to: CGPoint(x: 11.5, y: 4.7)); rings.addLine(to: CGPoint(x: 11.5, y: 9))
        rings.move(to: CGPoint(x: 20.5, y: 4.7)); rings.addLine(to: CGPoint(x: 20.5, y: 9))
        rings.move(to: CGPoint(x: 7.5, y: 11.4)); rings.addLine(to: CGPoint(x: 24.5, y: 11.4))
        stroke(rings, in: &context, width: 0.9)

        let blueLabel = Path(roundedRect: CGRect(x: 10, y: 15, width: 12, height: 4.8), cornerRadius: 1.2)
        context.fill(blueLabel, with: .color(LedgerPalette.accent))
        let check = Path { path in
            path.move(to: CGPoint(x: 12.3, y: 17.4))
            path.addLine(to: CGPoint(x: 14.4, y: 19))
            path.addLine(to: CGPoint(x: 19.6, y: 15.8))
        }
        context.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))

        var dots = Path()
        dots.addEllipse(in: CGRect(x: 11, y: 22, width: 1.6, height: 1.6))
        dots.addEllipse(in: CGRect(x: 15.2, y: 22, width: 1.6, height: 1.6))
        dots.addEllipse(in: CGRect(x: 19.4, y: 22, width: 1.6, height: 1.6))
        context.fill(
            dots,
            with: .color(colorScheme == .dark ? EntryCategoryAppearance.darkInk : .black.opacity(0.82))
        )
    }

    private func drawPrinterFee(in context: inout GraphicsContext) {
        let printer = Path(roundedRect: CGRect(x: 7, y: 12, width: 18, height: 12), cornerRadius: 2)
        stroke(printer, in: &context)
        let paper = Path(roundedRect: CGRect(x: 10, y: 6, width: 12, height: 9), cornerRadius: 1)
        stroke(paper, in: &context)
        let output = Path(roundedRect: CGRect(x: 10, y: 20, width: 12, height: 6), cornerRadius: 1)
        stroke(output, in: &context)
        var details = Path()
        details.move(to: CGPoint(x: 13, y: 9))
        details.addLine(to: CGPoint(x: 19, y: 9))
        details.move(to: CGPoint(x: 13, y: 12))
        details.addLine(to: CGPoint(x: 18, y: 12))
        stroke(details, in: &context, width: 1.25)
        stroke(Path(ellipseIn: CGRect(x: 20.5, y: 15.5, width: 1.8, height: 1.8)), in: &context, width: 1.1)
    }

    private func drawToiletPaper(in context: inout GraphicsContext) {
        let rolls = [
            (CGPoint(x: 16, y: 8.2), 7.5),
            (CGPoint(x: 11, y: 16.2), 8.4),
            (CGPoint(x: 21, y: 16.2), 8.4)
        ]
        for (center, height) in rolls {
            var body = Path()
            body.move(to: CGPoint(x: center.x - 4, y: center.y))
            body.addLine(to: CGPoint(x: center.x - 4, y: center.y + height))
            body.addCurve(to: CGPoint(x: center.x + 4, y: center.y + height), control1: CGPoint(x: center.x - 2, y: center.y + height + 1.6), control2: CGPoint(x: center.x + 2, y: center.y + height + 1.6))
            body.addLine(to: CGPoint(x: center.x + 4, y: center.y))
            stroke(body, in: &context)
            stroke(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 2.7, width: 8, height: 5.4)), in: &context)
            stroke(Path(ellipseIn: CGRect(x: center.x - 1.15, y: center.y - 0.8, width: 2.3, height: 1.6)), in: &context, width: 1.15)
            var perforation = Path()
            perforation.move(to: CGPoint(x: center.x - 4, y: center.y + height * 0.55))
            perforation.addLine(to: CGPoint(x: center.x + 4, y: center.y + height * 0.55))
            stroke(perforation, in: &context, width: 0.9)
        }
    }
}

private enum CategoryDarkIconRenderer {
    private static let cache = NSCache<NSString, UIImage>()
    private static let circleArtifactBands: [String: ClosedRange<CGFloat>] = [
        "expense-delivery": 0.335...0.380,
        "expense-transport": 0.290...0.325,
        "expense-leisure": 0.290...0.325,
        "expense-health": 0.335...0.370,
        "expense-catch-all": 0.335...0.390
    ]

    static func image(named name: String, usesDarkLinework: Bool) -> UIImage? {
        guard let original = UIImage(named: name) else { return nil }
        guard usesDarkLinework else { return original }

        let key = name as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let source = downsampled(original)
        let artifactBand = circleArtifactBands[name]
        let threshold: CGFloat = artifactBand == nil ? 0.56 : 0.13
        guard let result = recoloredLinework(
            in: source,
            maximumNeutralBrightness: threshold,
            removingCircleIn: artifactBand
        ) else { return original }
        cache.setObject(result, forKey: key)
        return result
    }

    private static func downsampled(_ image: UIImage) -> UIImage {
        let maximumDimension: CGFloat = 288
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longestSide = max(pixelSize.width, pixelSize.height)
        guard longestSide > maximumDimension else { return image }

        let ratio = maximumDimension / longestSide
        let targetSize = CGSize(
            width: max(1, (pixelSize.width * ratio).rounded()),
            height: max(1, (pixelSize.height * ratio).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func recoloredLinework(
        in image: UIImage,
        maximumNeutralBrightness: CGFloat,
        removingCircleIn artifactBand: ClosedRange<CGFloat>?
    ) -> UIImage? {
        guard let source = image.cgImage else { return nil }
        let width = source.width
        let height = source.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let output: CGImage? = pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let bitmapContext = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                          CGBitmapInfo.byteOrder32Big.rawValue
                  ) else { return nil }

            bitmapContext.interpolationQuality = .high
            bitmapContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
                if let artifactBand {
                    let pixelIndex = index / bytesPerPixel
                    let x = CGFloat(pixelIndex % width) + 0.5
                    let y = CGFloat(pixelIndex / width) + 0.5
                    let centerX = CGFloat(width) / 2
                    let centerY = CGFloat(height) / 2
                    let normalizedRadius = hypot(x - centerX, y - centerY) / CGFloat(min(width, height))
                    if artifactBand.contains(normalizedRadius) {
                        bytes[index] = 0
                        bytes[index + 1] = 0
                        bytes[index + 2] = 0
                        bytes[index + 3] = 0
                        continue
                    }
                }

                let alpha = CGFloat(bytes[index + 3]) / 255
                guard alpha > 0 else { continue }

                // The bitmap is premultiplied. Unpremultiply only for deciding
                // whether a pixel belongs to neutral dark linework, then write
                // the requested color using the exact original alpha.
                let red = min(1, CGFloat(bytes[index]) / 255 / alpha)
                let green = min(1, CGFloat(bytes[index + 1]) / 255 / alpha)
                let blue = min(1, CGFloat(bytes[index + 2]) / 255 / alpha)
                let maximum = max(red, green, blue)
                let minimum = min(red, green, blue)
                guard maximum - minimum < 0.10,
                      maximum < maximumNeutralBrightness else { continue }

                bytes[index] = UInt8((229 * alpha).rounded())
                bytes[index + 1] = UInt8((229 * alpha).rounded())
                bytes[index + 2] = UInt8((231 * alpha).rounded())
            }
            return bitmapContext.makeImage()
        }

        guard let output else { return nil }
        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }
}
