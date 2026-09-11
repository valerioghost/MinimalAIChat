import UIKit

/// Represents a single image attached to a chat message, persisted to disk.
struct ImageAttachment: Identifiable, Codable {
    let id: UUID
    let filename: String
    let createdAt: Date

    init(id: UUID = UUID(), filename: String, createdAt: Date = Date()) {
        self.id = id
        self.filename = filename
        self.createdAt = createdAt
    }
}

enum ImageAttachmentManager {

    private static let subdirectoryName = "ChatAttachments"
    private static let maxDimension: CGFloat = 1536.0
    private static let jpegQuality: CGFloat = 0.7

    private static var attachmentsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(subdirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(for filename: String) -> URL {
        attachmentsDirectory.appendingPathComponent(filename)
    }

    /// Resizes, compresses, and saves an image to disk, returning the attachment
    /// record to store on the ChatMessage. Mirrors ProfileImageManager's resize
    /// logic but writes a uniquely-named file instead of overwriting a fixed
    /// path, since a session can accumulate many attachments over time.
    /// Caller is responsible for dispatching off the main thread if needed —
    /// this function itself is synchronous.
    static func save(_ image: UIImage) -> ImageAttachment? {
        let maxSide = max(image.size.width, image.size.height)
        var targetSize = image.size
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = resizedImage.jpegData(compressionQuality: jpegQuality) else {
            return nil
        }

        let filename = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: fileURL(for: filename), options: .atomic)
        } catch {
            return nil
        }

        return ImageAttachment(filename: filename)
    }

    static func load(_ attachment: ImageAttachment) -> UIImage? {
        let url = fileURL(for: attachment.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Returns a base64 data URI ("data:image/jpeg;base64,...") ready to embed
    /// in an OpenAI-compatible `image_url` content part. Returns nil if the
    /// file is missing (e.g. deleted between save and send). Consumed in a
    /// later stage by ChatAPIService — not used anywhere in this stage.
    static func dataURI(for attachment: ImageAttachment) -> String? {
        let url = fileURL(for: attachment.filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    static func delete(_ attachment: ImageAttachment) {
        let url = fileURL(for: attachment.filename)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes a stored file by its raw filename, for cases where only the
    /// filename is known (e.g. purging orphans where no ImageAttachment
    /// struct exists anymore, only the file itself).
    static func delete(filename: String) {
        let url = fileURL(for: filename)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Returns the filenames of every image currently stored on disk in the
    /// attachments directory. Used at launch to find and remove orphaned
    /// files left behind by deleted sessions/messages (from before this
    /// cleanup existed, or from a hard app termination mid-save).
    static func listStoredFilenames() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: attachmentsDirectory.path) else {
            return []
        }
        return contents
    }
}
