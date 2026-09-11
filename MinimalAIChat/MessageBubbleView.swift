import SwiftUI
import UIKit
import PDFKit

/// A single chat bubble row — adapts layout and styling for user vs assistant.
struct MessageBubbleView: View {

    @EnvironmentObject private var settings: SettingsViewModel

    let message: ChatMessage
    var isSearching: Bool = false

    /// Controls the fullscreen image viewer, shown when the user taps an
    /// image attachment in the bubble.
    @State private var isShowingFullScreenImage = false

    /// Briefly true after tapping the copy button, to swap the icon to a
    /// checkmark as tap feedback before reverting.
    @State private var showCopiedFeedback = false

    /// Controls the file text preview sheet, shown when the user taps a
    /// file attachment chip in the bubble.
    @State private var isShowingFilePreview = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if isUser {
            userRow
        } else {
            assistantRow
        }
    }

    // MARK: - User bubble (right-aligned, coloured background)

    private var userRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 4) {
                if let attachment = message.imageAttachments.first,
                   let uiImage = ImageAttachmentManager.load(attachment) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .clipped()
                        .onTapGesture {
                            isShowingFullScreenImage = true
                        }
                        .fullScreenCover(isPresented: $isShowingFullScreenImage) {
                            FullScreenImageView(image: uiImage)
                        }
                }

                if let fileAttachment = message.fileAttachments.first {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 15))
                        Text(fileAttachment.displayName)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(settings.accentColor.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture {
                        isShowingFilePreview = true
                    }
                    .sheet(isPresented: $isShowingFilePreview) {
                        FileTextPreviewView(attachment: fileAttachment)
                    }
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(settings.accentColor)
                        .foregroundColor(.white)
                        .clipShape(BubbleShape(isUser: true))
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                }

                Text(formattedTime(message.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .opacity(0.7)
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    // MARK: - Assistant message (full-width, no background — ChatGPT style)

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 10) {
            // Small avatar anchored to the top-left
            avatarView

            VStack(alignment: .leading, spacing: 6) {
                if message.content.isEmpty {
                    if isSearching {
                        WebSearchIndicatorView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    } else {
                        TypingDotsView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                } else {
                    formattedContent(from: message.content)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Text(formattedTime(message.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .opacity(0.6)

                    if !message.content.isEmpty && !message.isWelcomeMessage {
                        Button(action: copyToClipboard) {
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .opacity(0.6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// Copies this message's raw text to the system clipboard and briefly
    /// swaps the button icon to a checkmark as tap feedback.
    private func copyToClipboard() {
        UIPasteboard.general.string = message.content
        withAnimation {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }

    /// A minimal, deliberately narrow block model. Only headings and unordered
    /// bullet items are recognized as distinct blocks; everything else — including
    /// tables, ordered/numbered lists, and code blocks — stays exactly as it
    /// rendered before, as plain paragraph text through the existing inline
    /// Markdown renderer. This keeps the change small and low-risk instead of
    /// trying to handle every possible construct different providers might emit.
    private enum ContentBlock {
        case heading(level: Int, text: String)
        case bulletItem(text: String)
        case paragraph(String)
    }

    /// Splits raw text into `ContentBlock`s, recognizing only `#`-style headings
    /// and `-`/`*`/`+` bullet items at the start of a line. Everything else is
    /// accumulated into paragraph blocks exactly as before (blank-line-separated,
    /// with single newlines converted to CommonMark hard-breaks).
    private func parseBlocks(from raw: String) -> [ContentBlock] {
        let normalised = raw.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r",   with: "\n")
        let lines = normalised.components(separatedBy: "\n")

        var blocks: [ContentBlock] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: "  \n")
            blocks.append(.paragraph(joined))
            paragraphBuffer.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = headingInfo(of: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let bulletText = bulletItemText(of: trimmed) {
                flushParagraph()
                blocks.append(.bulletItem(text: bulletText))
                continue
            }

            paragraphBuffer.append(line)
        }
        flushParagraph()

        return blocks
    }

    /// Recognizes `#` through `######` at the start of a line, requiring a space
    /// after the hashes (standard Markdown heading syntax).
    private func headingInfo(of line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#" {
            level += 1
            idx = line.index(after: idx)
        }
        guard level >= 1, level <= 6, idx < line.endIndex, line[idx] == " " else { return nil }
        let text = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    /// Recognizes `- `, `* `, or `+ ` at the start of a line. Deliberately does
    /// NOT handle ordered/numbered lists (`1. `), to avoid false positives with
    /// normal prose that happens to start with a number.
    private func bulletItemText(of line: String) -> String? {
        if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("* ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("+ ") { return String(line.dropFirst(2)) }
        return nil
    }

    /// Renders a single block's text as inline Markdown (bold/italic), exactly
    /// like the original renderer — this part is unchanged, just applied per
    /// block instead of to the whole message at once.
    private func inlineMarkdownText(from text: String) -> Text {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            options.allowsExtendedAttributes = true
            options.failurePolicy = .returnPartiallyParsedIfPossible
            let attrStr = try AttributedString(markdown: text, options: options)
            return Text(attrStr)
        } catch {
            return Text(text)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .system(size: 21, weight: .bold)
        case 2: return .system(size: 19, weight: .bold)
        default: return .system(size: 17, weight: .bold)
        }
    }

    /// Builds the full message content as a vertical stack of blocks — headings,
    /// bullet items, and paragraphs — replacing the old single-`Text` renderer.
    @ViewBuilder
    private func formattedContent(from raw: String) -> some View {
        let blocks = parseBlocks(from: raw)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    inlineMarkdownText(from: text)
                        .font(headingFont(for: level))
                        .fixedSize(horizontal: false, vertical: true)

                case .bulletItem(let text):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        inlineMarkdownText(from: text)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                case .paragraph(let text):
                    inlineMarkdownText(from: text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }


    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [settings.accentColor, settings.accentColor.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 30, height: 30)
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Helpers

    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}



// MARK: - Bubble Shape

/// A rounded rectangle with one corner slightly less rounded to simulate a "tail".
struct BubbleShape: Shape {

    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let smallR: CGFloat = 4

        var path = Path()

        if isUser {
            // Top-left, top-right, bottom-left fully rounded; bottom-right small
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - smallR))
            path.addArc(center: CGPoint(x: rect.maxX - smallR, y: rect.maxY - smallR), radius: smallR, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // Top-right, bottom-right, bottom-left fully rounded; top-left small
            path.move(to: CGPoint(x: rect.minX + smallR, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + smallR))
            path.addArc(center: CGPoint(x: rect.minX + smallR, y: rect.minY + smallR), radius: smallR, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Typing Dots View

struct TypingDotsView: View {
    @State private var phase: Int = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phase == i ? 1.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 0.35).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
        .frame(height: 20)
    }
}

// MARK: - Web Search Indicator View

struct WebSearchIndicatorView: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isPulsing ? 12 : -12))
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Text("Searching the web…")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .opacity(isPulsing ? 0.5 : 1.0)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isPulsing
                )
        }
        .frame(height: 20)
        .onAppear { isPulsing = true }
    }
}

// MARK: - Full Screen Image Viewer

/// Presented full-screen when the user taps an image attachment in a chat
/// bubble. Always shows the complete, uncropped image (scaledToFit) over a
/// black background — separate from the bubble's cropped thumbnail, which
/// is unaffected by this view. Dismissible by tapping the image or the
/// close button.
struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture {
                    presentationMode.wrappedValue.dismiss()
                }

            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.85))
                    .background(Circle().fill(Color.black.opacity(0.3)))
            }
            .padding(.top, 16)
            .padding(.leading, 20)
        }
    }
}

// MARK: - PDF Document Viewer

/// Wraps PDFKit's PDFView to render an actual PDF with its real formatting,
/// layout, and embedded images — used instead of the plain-text preview
/// whenever a PDF's original bytes were persisted (see
/// FileAttachmentManager.pdfFileURL(for:)).
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - File Text Preview

/// Shown when the user taps a file attachment chip in a chat bubble.
/// Displays the extracted text that was actually sent to the model — not
/// the original file, since only extracted text is persisted (see
/// FileAttachmentManager). Monospaced font suits both prose and source code
/// reasonably well without needing per-file-type formatting.
struct FileTextPreviewView: View {
    let attachment: FileAttachment
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            Group {
                // Prefer the real, formatted PDF when its original bytes
                // were persisted (Stage A of this feature). Falls back to
                // the plain extracted text for TXT/Markdown/code files, and
                // for PDFs saved before this feature existed (no original
                // bytes stored for those — text-only is the best we can do).
                if let pdfURL = FileAttachmentManager.pdfFileURL(for: attachment) {
                    PDFKitView(url: pdfURL)
                } else {
                    ScrollView {
                        Text(FileAttachmentManager.loadText(attachment) ?? "This file's content is no longer available.")
                            .font(.system(size: 14, design: .monospaced))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .navigationTitle(attachment.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct MessageBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            MessageBubbleView(message: ChatMessage(role: .assistant, content: "Hello! How can I help you today?"))
            MessageBubbleView(message: ChatMessage(role: .user, content: "Can you explain SwiftUI?"))
            MessageBubbleView(message: ChatMessage(role: .assistant, content: "Sure! SwiftUI is Apple's declarative UI framework, introduced in 2019. It lets you build beautiful user interfaces across all Apple platforms with very little code."))
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
