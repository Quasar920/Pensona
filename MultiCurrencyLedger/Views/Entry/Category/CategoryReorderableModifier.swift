import SwiftUI

extension View {
    @ViewBuilder
    func categoryReorderable(
        isEnabled: Bool,
        itemID: UUID,
        acceptDrop: @escaping ([String]) -> Bool
    ) -> some View {
        if isEnabled {
            draggable(itemID.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    return acceptDrop(items)
                }
        } else {
            self
        }
    }
}
