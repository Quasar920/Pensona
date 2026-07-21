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
                Image(systemName: category.symbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
            }
        }
        .frame(width: size, height: size)
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
