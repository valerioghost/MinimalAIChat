import SwiftUI

/// A single chat bubble row — adapts layout and styling for user vs assistant.
struct MessageBubbleView: View {

    let message: ChatMessage

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
                Text(message.content)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(BubbleShape(isUser: true))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)

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
                    TypingDotsView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                } else {
                    markdownText(from: message.content)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(formattedTime(message.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .opacity(0.6)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// Converts a raw API response string into a SwiftUI `Text` with Markdown rendering.
    ///
    /// Strategy:
    ///   1. Replace single `\n` (that are NOT already part of a blank-line paragraph break)
    ///      with two trailing spaces + `\n`. This is the CommonMark hard-break syntax, which
    ///      forces `AttributedString` to honour every newline instead of collapsing them into
    ///      a space.
    ///   2. Parse the resulting string with `AttributedString(markdown:)`.
    ///   3. Fall back to a plain `Text` if parsing throws.
    private func markdownText(from raw: String) -> Text {
        // Normalise Windows-style line endings first
        let normalised = raw.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r",   with: "\n")

        // Convert every single newline into a CommonMark hard-break.
        // A "hard break" is two spaces followed by \n.
        // We must NOT double-convert lines that are already blank (i.e. \n\n).
        // Approach: split on blank lines (paragraph boundaries), process each paragraph,
        // then rejoin with blank lines.
        let paragraphs = normalised.components(separatedBy: "\n\n")
        let processed = paragraphs.map { paragraph -> String in
            // Within a paragraph, turn each \n into a hard-break \n
            // but leave fenced code blocks untouched.
            paragraph.replacingOccurrences(of: "\n", with: "  \n")
        }.joined(separator: "\n\n")

        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .full
            options.allowsExtendedAttributes = true
            options.failurePolicy = .returnPartiallyParsedIfPossible
            let attrStr = try AttributedString(markdown: processed, options: options)
            return Text(attrStr)
        } catch {
            // Fallback: plain text preserves spaces/newlines without any rendering glitches
            return Text(raw)
        }
    }


    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
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
