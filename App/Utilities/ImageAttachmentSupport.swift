import AppKit
import Foundation
import UniformTypeIdentifiers

enum ImageAttachmentSupport {
    static func attachmentsFromPasteboard() -> [ChatImageAttachment] {
        let pasteboard = NSPasteboard.general

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            return images.compactMap { image in
                makeAttachment(from: image, filename: nil)
            }
        }

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            return fileURLs.compactMap(loadAttachment(from:))
        }

        return []
    }

    static func loadAttachments(from providers: [NSItemProvider]) async -> [ChatImageAttachment] {
        var attachments: [ChatImageAttachment] = []

        for provider in providers {
            if let attachment = await loadAttachment(from: provider) {
                attachments.append(attachment)
            }
        }

        return attachments
    }

    static func loadAttachment(from fileURL: URL) -> ChatImageAttachment? {
        guard let type = UTType(filenameExtension: fileURL.pathExtension),
              type.conforms(to: .image),
              let image = NSImage(contentsOf: fileURL) else {
            return nil
        }

        return makeAttachment(from: image, filename: fileURL.lastPathComponent)
    }

    static func makeAttachment(from image: NSImage, filename: String?) -> ChatImageAttachment? {
        guard let data = image.pngData() else {
            return nil
        }

        return ChatImageAttachment(
            data: data,
            mimeType: "image/png",
            filename: filename
        )
    }

    private static func loadAttachment(from provider: NSItemProvider) async -> ChatImageAttachment? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let fileURL = await loadFileURL(from: provider),
           let attachment = loadAttachment(from: fileURL) {
            return attachment
        }

        for imageType in [UTType.png, .jpeg, .tiff, .gif, .webP] {
            if provider.hasItemConformingToTypeIdentifier(imageType.identifier),
               let image = await loadImage(from: provider, typeIdentifier: imageType.identifier),
               let attachment = makeAttachment(from: image, filename: nil) {
                return attachment
            }
        }

        return nil
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = NSURL(
                    absoluteURLWithDataRepresentation: data,
                    relativeTo: nil
                   ) as URL? {
                    continuation.resume(returning: url)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private static func loadImage(from provider: NSItemProvider, typeIdentifier: String) async -> NSImage? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                guard let data, let image = NSImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
