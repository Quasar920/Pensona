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
                .fill(.regularMaterial)
                .overlay(Color(uiColor: .systemBackground).opacity(0.18))
                .onTapGesture(perform: close)

            VStack(spacing: 14) {
                HStack {
                    Text(parent.localizedName(locale: locale)).font(.headline)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
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
                            Image(systemName: "plus").font(.headline)
                            Text("新分类").font(.caption2.weight(.semibold)).lineLimit(2)
                        }
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? 104 : 76, height: 64)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
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
                .stroke(.white.opacity(0.32), lineWidth: 0.8)
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
            .foregroundStyle(selectedID == child.id ? Color.accentColor : .primary)
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 104 : 76, height: 64)
            .background(
                selectedID == child.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
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
