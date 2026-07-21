import Foundation
import UIKit

enum CategoryIconError: LocalizedError, Equatable {
    case emptyData
    case fileTooLarge
    case unsupportedImage
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .emptyData: AppLocalization.string( "图片内容为空")
        case .fileTooLarge: AppLocalization.string( "分类图标不能超过 20 MB")
        case .unsupportedImage: AppLocalization.string( "无法读取这张分类图标")
        case .invalidPath: AppLocalization.string( "分类图标路径无效")
        }
    }
}

enum CategoryIconRenderingMode: String, CaseIterable, Sendable {
    case original
    case monochrome
}

struct StoredCategoryIcon: Equatable, Sendable {
    let originalRelativePath: String
    let thumbnailRelativePath: String
    let thumbnailPixelSize: Int
}

@MainActor
struct CategoryIconStore {
    static let maximumBytes = 20 * 1_024 * 1_024
    static let thumbnailPixels = 144
    static let maximumOriginalPixels = 1_024

    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.rootURL = support
                .appendingPathComponent("MultiCurrencyLedger", isDirectory: true)
                .appendingPathComponent("CategoryIcons", isDirectory: true)
        }
    }

    func saveImage(
        _ data: Data,
        categoryID: UUID,
        renderingMode: CategoryIconRenderingMode
    ) throws -> StoredCategoryIcon {
        guard !data.isEmpty else { throw CategoryIconError.emptyData }
        guard data.count <= Self.maximumBytes else { throw CategoryIconError.fileTooLarge }
        guard let decoded = UIImage(data: data), decoded.size.width > 0, decoded.size.height > 0 else {
            throw CategoryIconError.unsupportedImage
        }

        let square = squareCropped(decoded)
        let rendered = renderingMode == .monochrome ? monochrome(square) : square
        let original = resized(rendered, pixels: Self.maximumOriginalPixels)
        let thumbnail = resized(rendered, pixels: Self.thumbnailPixels)
        guard let originalData = original.pngData(), let thumbnailData = thumbnail.pngData() else {
            throw CategoryIconError.unsupportedImage
        }

        let directory = categoryID.uuidString.lowercased()
        let originalPath = "\(directory)/original.png"
        let thumbnailPath = "\(directory)/thumbnail.png"
        let originalURL = try url(for: originalPath)
        let thumbnailURL = try url(for: thumbnailPath)
        try fileManager.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try originalData.write(to: originalURL, options: .atomic)
        do {
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: originalURL.deletingLastPathComponent())
            throw error
        }
        return StoredCategoryIcon(
            originalRelativePath: originalPath,
            thumbnailRelativePath: thumbnailPath,
            thumbnailPixelSize: Self.thumbnailPixels
        )
    }

    func url(for relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              !relativePath.hasPrefix("/"),
              !components.contains(".."),
              UUID(uuidString: String(components[0])) != nil,
              ["original.png", "thumbnail.png"].contains(String(components[1])) else {
            throw CategoryIconError.invalidPath
        }
        let standardizedRoot = rootURL.standardizedFileURL
        let resolved = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard resolved.path.hasPrefix(standardizedRoot.path + "/") else {
            throw CategoryIconError.invalidPath
        }
        return resolved
    }

    func thumbnail(relativePath: String) throws -> UIImage {
        let fileURL = try url(for: relativePath)
        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            throw CategoryIconError.unsupportedImage
        }
        return image
    }

    func removeIconSet(relativePath: String) throws {
        let fileURL = try url(for: relativePath)
        let directory = fileURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    func removeIfUnreferenced(
        relativePath: String,
        categories: [LedgerCategory]
    ) throws {
        guard !categories.contains(where: { $0.userIconRelativePath == relativePath }) else { return }
        try removeIconSet(relativePath: relativePath)
    }

    private func squareCropped(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let origin = CGPoint(
            x: (image.size.width - side) / 2,
            y: (image.size.height - side) / 2
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
    }

    private func resized(_ image: UIImage, pixels: Int) -> UIImage {
        let side = min(CGFloat(pixels), max(image.size.width, image.size.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: side, height: side)))
        }
    }

    private func monochrome(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: image.size)
            UIColor.black.setFill()
            context.cgContext.fill(rect)
            image.withRenderingMode(.alwaysTemplate).draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }
}
