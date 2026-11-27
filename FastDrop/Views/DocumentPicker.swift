import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A document picker that properly handles security-scoped resource access for sandboxed environments like LiveContainer.
struct DocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    init(
        allowedContentTypes: [UTType] = [.item],
        allowsMultipleSelection: Bool = true,
        onPick: @escaping ([URL]) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.allowedContentTypes = allowedContentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // For iOS, start accessing security-scoped resources immediately
            // The caller is responsible for calling stopAccessingSecurityScopedResource when done
            var processedURLs: [URL] = []

            for url in urls {
                // Start accessing security-scoped resource
                let accessed = url.startAccessingSecurityScopedResource()
                // Note: We don't stop accessing here - the URLs are returned and the consumer
                // must call stopAccessingSecurityScopedResource() when done with them
                processedURLs.append(url)
            }

            onPick(processedURLs)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

/// Security-scoped URL wrapper that manages access lifecycle
final class SecurityScopedURL: @unchecked Sendable {
    let url: URL
    private var isAccessing = false

    init(url: URL) {
        self.url = url
    }

    func startAccessing() -> Bool {
        guard !isAccessing else { return true }
        isAccessing = url.startAccessingSecurityScopedResource()
        return isAccessing
    }

    func stopAccessing() {
        guard isAccessing else { return }
        url.stopAccessingSecurityScopedResource()
        isAccessing = false
    }

    deinit {
        stopAccessing()
    }
}

/// Extension to handle security-scoped URLs in file operations
extension URL {
    /// Perform a block with security-scoped access
    func withSecurityScopedAccess<T>(_ block: () throws -> T) rethrows -> T {
        let accessed = startAccessingSecurityScopedResource()
        defer {
            if accessed {
                stopAccessingSecurityScopedResource()
            }
        }
        return try block()
    }
}