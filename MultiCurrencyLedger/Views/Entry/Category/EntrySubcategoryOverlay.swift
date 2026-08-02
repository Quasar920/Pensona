import SwiftUI

struct EntrySubcategoryOverlay: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    let parent: LedgerCategory
    let children: [LedgerCategory]
    let selectedID: UUID?
    let isReordering: Bool
    let select: (LedgerCategory) -> Void
    let add: () -> Void
    let longPress: (LedgerCategory) -> Void
    let reorder: (UUID, UUID) -> Void
    let close: () -> Void

    private var columnCount: Int { dynamicTypeSize.isAccessibilitySize ? 2 : 4 }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(EntryCategoryAppearance.overlay)
                .onTapGesture(perform: close)

            VStack(spacing: 14) {
                HStack {
                    Text(parent.localizedName(locale: locale))
                        .font(.headline)
                        .foregroundStyle(EntryCategoryAppearance.ink)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .tint(EntryCategoryAppearance.ink)
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(dynamicTypeSize.isAccessibilitySize ? 104 : 76)), count: columnCount),
                    spacing: 12
                ) {
                    ForEach(children) { child in
                        tile(child)
                    }
                    Button(action: add) {
                        VStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.headline)
                                .foregroundStyle(LedgerPalette.accent)
                            Text("新分类")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(2)
                                .foregroundStyle(EntryCategoryAppearance.ink)
                        }
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? 104 : 76, height: 64)
                        .background(EntryCategoryAppearance.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(LedgerGlassPressStyle())
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
        }
    }

    private func tile(_ child: LedgerCategory) -> some View {
        Button { select(child) } label: {
            VStack(spacing: 5) {
                CategoryIconImage(category: child, size: 28)
                Text(child.localizedName(locale: locale))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(selectedID == child.id ? LedgerPalette.accent : EntryCategoryAppearance.ink)
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 104 : 76, height: 64)
            .background(
                EntryCategoryAppearance.card,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selectedID == child.id ? LedgerPalette.accent.opacity(0.75) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(LedgerGlassPressStyle())
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 1)
                .onEnded { _ in longPress(child) }
        )
        .categoryReorderable(isEnabled: isReordering, itemID: child.id) { items in
            guard isReordering,
                  let raw = items.first,
                  let sourceID = UUID(uuidString: raw) else { return false }
            reorder(sourceID, child.id)
            return true
        }
        .rotationEffect(isReordering ? .degrees(child.id.uuidString.hashValue.isMultiple(of: 2) ? 1.2 : -1.2) : .zero)
        .animation(
            isReordering ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .default,
            value: isReordering
        )
    }
}
