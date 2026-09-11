import SwiftUI
import UIKit

/// Bottom input bar: expanding TextEditor + send button + optional image
/// and/or file attachment.
struct InputBarView: View {

    @EnvironmentObject private var viewModel: ChatViewModel
    @EnvironmentObject private var settings: SettingsViewModel
    @FocusState private var isTextFieldFocused: Bool

    @State private var pendingImage: UIImage?
    @State private var pendingFile: FileAttachment?
    @State private var showAttachmentSourceMenu = false
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var fileErrorMessage: String?

    // Height constraints for the text editor
    private let minHeight: CGFloat = 38
    private let maxHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ── Pending Attachments Preview ─────────────────────────────────
            if pendingImage != nil || pendingFile != nil {
                HStack(spacing: 8) {
                    if let pendingImage {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: pendingImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .clipped()

                            Button(action: { self.pendingImage = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .offset(x: 6, y: -6)
                        }
                    }

                    if let pendingFile {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 16))
                                .foregroundColor(settings.accentColor)
                            Text(pendingFile.displayName)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button(action: { self.pendingFile = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.leading, 12)
            }

            HStack(alignment: .center, spacing: 10) {

                // ── Attachment Button ────────────────────────────────────────
                Button(action: { showAttachmentSourceMenu = true }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(settings.accentColor)
                        .frame(width: 38, height: 38)
                }
                .confirmationDialog("Add File", isPresented: $showAttachmentSourceMenu, titleVisibility: .visible) {
                    Button("Photo Library") {
                        imagePickerSourceType = .photoLibrary
                        showImagePicker = true
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Camera") {
                            imagePickerSourceType = .camera
                            showImagePicker = true
                        }
                    }
                    Button("Browse Files") {
                        showDocumentPicker = true
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .sheet(isPresented: $showImagePicker) {
                    SystemImagePicker(selectedImage: $pendingImage, sourceType: imagePickerSourceType, allowsEditing: false)
                        .ignoresSafeArea()
                }
                .sheet(isPresented: $showDocumentPicker) {
                    SystemDocumentPicker(onPick: handlePickedFile)
                        .ignoresSafeArea()
                }
                .alert("Can't Attach File", isPresented: Binding(
                    get: { fileErrorMessage != nil },
                    set: { if !$0 { fileErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { fileErrorMessage = nil }
                } message: {
                    Text(fileErrorMessage ?? "")
                }

                // ── Dynamic Text Input ────────────────────────────────────────
                ZStack(alignment: .leading) {
                    // Placeholder
                    if viewModel.inputText.isEmpty {
                        Text("Message")
                            .foregroundColor(Color(.placeholderText))
                            .font(.system(size: 16))
                            .padding(.leading, 6)
                            .allowsHitTesting(false)
                    }

                    // TextEditor grows up to maxHeight, then scrolls internally
                    TextEditor(text: $viewModel.inputText)
                        .font(.system(size: 16))
                        .frame(minHeight: minHeight, maxHeight: maxHeight)
                        .fixedSize(horizontal: false, vertical: true)
                        .focused($isTextFieldFocused)
                        .scrollContentBackgroundHidden()   // custom extension below
                        .padding(.vertical, 4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                // ── Send Button ───────────────────────────────────────────────
                Button(action: sendTapped) {
                    ZStack {
                        Circle()
                            .fill(canSend ? settings.accentColor : Color(.tertiarySystemFill))
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(canSend ? .white : Color(.tertiaryLabel))
                    }
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.15), value: canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: -2)
        )
    }

    // MARK: - Helpers

    private var canSend: Bool {
        let hasText = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || pendingImage != nil || pendingFile != nil) && !viewModel.isTyping
    }

    private func sendTapped() {
        viewModel.sendMessage(image: pendingImage, file: pendingFile)
        pendingImage = nil
        pendingFile = nil
        // Dismiss the keyboard immediately when the user sends a message.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        isTextFieldFocused = true
    }

    /// Extracts and validates the picked file, storing it as a pending
    /// attachment on success or surfacing an error alert on failure (too
    /// large, or unreadable/no extractable text — e.g. a scanned PDF).
    private func handlePickedFile(_ url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        switch FileAttachmentManager.save(from: url) {
        case .success(let attachment):
            pendingFile = attachment
        case .failure(.unreadable):
            fileErrorMessage = "This file couldn't be read as text. Scanned PDFs with no selectable text aren't supported yet."
        case .failure(.tooLarge(let characterCount, let limit)):
            fileErrorMessage = "This file is too large (\(characterCount) characters, limit is \(limit))."
        }
    }
}

// MARK: - ScrollContentBackground helper (iOS 16 compat shim)

private extension View {
    /// On iOS 16+ hides the TextEditor default background.
    /// On iOS 15, we replicate the effect by making the background clear via UITextView appearance.
    func scrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            return AnyView(self.scrollContentBackground(.hidden))
        } else {
            return AnyView(self.onAppear {
                UITextView.appearance().backgroundColor = .clear
            })
        }
    }
}

// MARK: - Preview

struct InputBarView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsViewModel()
        VStack {
            Spacer()
            InputBarView()
        }
        .environmentObject(ChatViewModel(settings: settings))
        .ignoresSafeArea(edges: .bottom)
    }
}
