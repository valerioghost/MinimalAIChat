import Foundation
import PDFKit

/// Represents a single text-extractable file (PDF, plain text, or source
/// code) attached to a chat message. Unlike images, what's persisted and
/// sent to the model is the EXTRACTED TEXT, not the original file — there is
/// no universal, provider-agnostic way to send a raw file through the
/// OpenAI-compatible /chat/completions endpoint, but plain text works with
/// every provider regardless of multimodal support.
struct FileAttachment: Identifiable, Codable {
    let id: UUID
    /// Original filename as picked by the user (for display in the UI), e.g. "report.pdf".
    let displayName: String
    /// Name of the on-disk cache file holding the extracted text, e.g. "<uuid>.txt".
    let storedFilename: String
    /// Character count of the extracted text, cached at save time so callers
    /// (e.g. history-trimming budget logic) don't need to re-read the file
    /// from disk just to measure its size.
    let characterCount: Int
    let createdAt: Date
    /// Name of the on-disk cache file holding the ORIGINAL PDF bytes, e.g.
    /// "<uuid>.pdf" — only set when the source file was a PDF; nil for
    /// TXT/Markdown/code attachments, which have no separate "original" to
    /// preserve beyond their already-stored extracted text. Optional, so old
    /// persisted attachments (saved before this field existed) decode safely
    /// as nil via Swift's automatic Codable synthesis for Optional
    /// properties — no custom Codable implementation needed here.
    var originalPDFFilename: String? = nil

    init(id: UUID = UUID(), displayName: String, storedFilename: String, characterCount: Int, createdAt: Date = Date(), originalPDFFilename: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.storedFilename = storedFilename
        self.characterCount = characterCount
        self.createdAt = createdAt
        self.originalPDFFilename = originalPDFFilename
    }
}

enum FileAttachmentError: Error {
    case unreadable
    case tooLarge(characterCount: Int, limit: Int)
}

enum FileAttachmentManager {

    private static let subdirectoryName = "ChatFileAttachments"
    /// Hard cap on extracted text length. Chosen as a generous but bounded
    /// default for a single document (~12-15k tokens for most models),
    /// independent from the conversation history character budget, which is
    /// a separate, per-turn concern. Oversized files are rejected outright
    /// (never truncated), per product decision.
    static let maxCharacterCount = 50_000

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

    /// Extracts plain text from a user-picked file. PDFs are read page by
    /// page via PDFKit; everything else is treated as UTF-8 text (covers
    /// .txt, .md, and virtually all source code file extensions). Returns
    /// nil if the file can't be read as text at all (e.g. a scanned PDF with
    /// no selectable text, or a genuinely binary file) — this is a known
    /// limitation: no OCR support in this version.
    private static func extractText(from url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { return nil }
            var combined = ""
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                if let pageText = page.string {
                    combined += pageText + "\n"
                }
            }
            let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Reads and validates a user-picked file, returning a persisted
    /// FileAttachment on success. Callers are responsible for calling
    /// `url.startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`
    /// around this call when `url` comes from UIDocumentPickerViewController,
    /// since files outside the app sandbox (iCloud Drive, other providers)
    /// require that access scope.
    static func save(from url: URL) -> Result<FileAttachment, FileAttachmentError> {
        guard let text = extractText(from: url) else {
            return .failure(.unreadable)
        }
        guard text.count <= maxCharacterCount else {
            return .failure(.tooLarge(characterCount: text.count, limit: maxCharacterCount))
        }

        let storedFilename = "\(UUID().uuidString).txt"
        do {
            try text.write(to: fileURL(for: storedFilename), atomically: true, encoding: .utf8)
        } catch {
            return .failure(.unreadable)
        }

        // For PDFs, also persist the original bytes so a real, formatted
        // preview can be shown later — separate from the extracted text
        // cache above, which is what's actually sent to the model. If this
        // copy fails for any reason, we don't fail the whole save (the text
        // extraction already succeeded, which is the core requirement) —
        // the attachment just falls back to a text-only preview.
        var originalPDFFilename: String? = nil
        if url.pathExtension.lowercased() == "pdf" {
            let pdfFilename = "\(UUID().uuidString).pdf"
            if let pdfData = try? Data(contentsOf: url) {
                if (try? pdfData.write(to: fileURL(for: pdfFilename), options: .atomic)) != nil {
                    originalPDFFilename = pdfFilename
                }
            }
        }

        let attachment = FileAttachment(
            displayName: url.lastPathComponent,
            storedFilename: storedFilename,
            characterCount: text.count,
            originalPDFFilename: originalPDFFilename
        )
        return .success(attachment)
    }

    /// Loads the extracted text back from disk, e.g. when building the
    /// outgoing API request. Returns nil if the file is missing.
    static func loadText(_ attachment: FileAttachment) -> String? {
        let url = fileURL(for: attachment.storedFilename)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Returns the on-disk URL of the original PDF bytes for this
    /// attachment, if any were stored. Returns nil for non-PDF attachments,
    /// for PDFs saved before this feature existed, or if the file is
    /// missing — callers should fall back to the text-only preview in any
    /// of these cases.
    static func pdfFileURL(for attachment: FileAttachment) -> URL? {
        guard let originalPDFFilename = attachment.originalPDFFilename else { return nil }
        let url = fileURL(for: originalPDFFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static func delete(_ attachment: FileAttachment) {
        let url = fileURL(for: attachment.storedFilename)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        if let originalPDFFilename = attachment.originalPDFFilename {
            let pdfURL = fileURL(for: originalPDFFilename)
            if FileManager.default.fileExists(atPath: pdfURL.path) {
                try? FileManager.default.removeItem(at: pdfURL)
            }
        }
    }

    static func delete(filename: String) {
        let url = fileURL(for: filename)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func listStoredFilenames() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: attachmentsDirectory.path) else {
            return []
        }
        return contents
    }
}
