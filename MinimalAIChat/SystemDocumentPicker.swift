import SwiftUI
import UniformTypeIdentifiers

/// Wraps UIDocumentPickerViewController to let the user pick a PDF or text
/// file from the Files app. Uses `asCopy: true`, which copies the picked
/// file into an app-managed temporary location — this avoids needing
/// security-scoped resource access for files coming from iCloud Drive or
/// other providers, since the copy already lives inside the app sandbox.
struct SystemDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let allowedTypes: [UTType] = [.pdf, .text]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: SystemDocumentPicker

        init(_ parent: SystemDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}
