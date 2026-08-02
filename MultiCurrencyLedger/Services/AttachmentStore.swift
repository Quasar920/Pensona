import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

enum AttachmentError: LocalizedError, Equatable {
    case emptyData
    case fileTooLarge
    case unsupportedImage
    case missingBook
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .emptyData: AppLocalization.string( "图片内容为空")
        case .fileTooLarge: AppLocalization.string( "单张图片不能超过 20 MB")
        case .unsupportedImage: AppLocalization.string( "仅支持 JPEG、PNG、HEIC 和 GIF 图片")
        case .missingBook: AppLocalization.string( "交易未归属账本")
        case .invalidPath: AppLocalization.string( "附件路径无效")
        }
    }
}

struct StoredAttachmentFile: Equatable {
    let relativePath: String
    let mimeType: String
    let byteCount: Int
}

struct AttachmentStore {
    static let maximumBytes = 20 * 1_024 * 1_024

    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.rootURL = applicationSupport
                .appendingPathComponent("MultiCurrencyLedger", isDirectory: true)
                .appendingPathComponent("Attachments", isDirectory: true)
        }
    }

    func saveImage(
        _ data: Data,
        bookID: UUID,
        transactionID: UUID,
        attachmentID: UUID
    ) throws -> StoredAttachmentFile {
        guard !data.isEmpty else { throw AttachmentError.emptyData }
        guard data.count <= Self.maximumBytes else { throw AttachmentError.fileTooLarge }
        guard let format = Self.imageFormat(data) else { throw AttachmentError.unsupportedImage }

        let relativePath = [
            bookID.uuidString.lowercased(),
            transactionID.uuidString.lowercased(),
            "\(attachmentID.uuidString.lowercased()).\(format.extensionName)"
        ].joined(separator: "/")
        let destination = try url(for: relativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        return StoredAttachmentFile(
            relativePath: relativePath,
            mimeType: format.mimeType,
            byteCount: data.count
        )
    }

    func url(for relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/")
        guard !components.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains("..") else {
            throw AttachmentError.invalidPath
        }
        let standardizedRoot = rootURL.standardizedFileURL
        let resolved = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard resolved.path.hasPrefix(standardizedRoot.path + "/") else {
            throw AttachmentError.invalidPath
        }
        return resolved
    }

    func remove(relativePath: String) throws {
        let fileURL = try url(for: relativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    static func imageFormat(_ data: Data) -> (extensionName: String, mimeType: String)? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return ("jpg", "image/jpeg") }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ("png", "image/png") }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return ("gif", "image/gif") }
        if bytes.count >= 12,
           String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
            return ("heic", "image/heic")
        }
        return nil
    }
}

enum AttachmentImageProcessor {
    private static let preferredMaximumBytes = 12 * 1_024 * 1_024

    static func preparedData(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw AttachmentError.emptyData }
        if data.count <= AttachmentStore.maximumBytes,
           AttachmentStore.imageFormat(data) != nil {
            return data
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AttachmentError.unsupportedImage
        }

        var smallestResult: Data?
        for maximumPixelSize in [4_096, 3_072, 2_560, 2_048] {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: false
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions as CFDictionary
            ) else {
                continue
            }

            for quality in [0.86, 0.74, 0.62, 0.50] {
                guard let encoded = jpegData(image, quality: quality) else { continue }
                if smallestResult == nil || encoded.count < smallestResult!.count {
                    smallestResult = encoded
                }
                if encoded.count <= preferredMaximumBytes {
                    return encoded
                }
            }
        }

        guard let smallestResult else { throw AttachmentError.unsupportedImage }
        guard smallestResult.count <= AttachmentStore.maximumBytes else {
            throw AttachmentError.fileTooLarge
        }
        return smallestResult
    }

    private static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

@MainActor
final class AttachmentService {
    private let context: ModelContext
    private let store: AttachmentStore

    init(context: ModelContext, store: AttachmentStore = AttachmentStore()) {
        self.context = context
        self.store = store
    }

    @discardableResult
    func addImage(
        data: Data,
        originalFilename: String = "照片",
        to transaction: LedgerTransaction
    ) throws -> TransactionAttachment {
        try LedgerBookAccess.requireActiveBook(in: context, for: transaction)
        guard let bookID = transaction.bookID else {
            throw AttachmentError.missingBook
        }
        let preparedData = try AttachmentImageProcessor.preparedData(data)
        let id = UUID()
        let stored = try store.saveImage(
            preparedData,
            bookID: bookID,
            transactionID: transaction.id,
            attachmentID: id
        )
        let attachment = TransactionAttachment(
            id: id,
            transactionID: transaction.id,
            bookID: bookID,
            relativePath: stored.relativePath,
            originalFilename: originalFilename,
            mimeType: stored.mimeType,
            byteCount: stored.byteCount
        )
        context.insert(attachment)
        do {
            try context.save()
            return attachment
        } catch {
            try? store.remove(relativePath: stored.relativePath)
            context.rollback()
            throw error
        }
    }

    func remove(_ attachment: TransactionAttachment) throws {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: attachment.bookID)
        let path = attachment.relativePath
        context.delete(attachment)
        try context.save()
        try? store.remove(relativePath: path)
    }

    func fileURL(for attachment: TransactionAttachment) throws -> URL {
        try store.url(for: attachment.relativePath)
    }
}
