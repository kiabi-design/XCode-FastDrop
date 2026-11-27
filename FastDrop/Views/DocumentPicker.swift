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
        // Enable folder picking
        if #available(iOS 16.0, *) {
            picker.contentTypes = allowedContentTypes
        }
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
            // Process each URL with security-scoped resource access
            var processedURLs: [URL] = []

            for url in urls {
                // Start accessing security-scoped resource
                let accessed = url.startAccessingSecurityScopedResource()

                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                // Try to resolve bookmarks for persistent access
                if let resolvedURL = resolveBookmark(for: url) {
                    processedURLs.append(resolvedURL)
                } else {
                    // Create bookmark for future access
                    if let bookmarkURL = createBookmark(for: url) {
                        processedURLs.append(bookmarkURL)
                    } else {
                        processedURLs.append(url)
                    }
                }
            }

            onPick(processedURLs)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }

        /// Resolve a security-scoped bookmark for persistent access
        private func resolveBookmark(for url: URL) -> URL? {
            guard let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(url.lastPathComponent)") else {
                return nil
            }

            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    // Bookmark is stale, try to create a new one
                    return createBookmark(for: url)
                }

                // Start accessing the resolved URL
                _ = resolvedURL.startAccessingSecurityScopedResource()
                return resolvedURL
            } catch {
                return nil
            }
        }

        /// Create a security-scoped bookmark for persistent access
        private func createBookmark(for url: URL) -> URL? {
            do {
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                UserDefaults.standard.set(bookmarkData, forKey: "bookmark_\(url.lastPathComponent)")

                // Start accessing the original URL
                _ = url.startAccessingSecurityScopedResource()
                return url
            } catch {
                return nil
            }
        }
    }
}

/// A simpler document picker using PHPicker for images/media or standard file picking
struct FilePicker: UIViewControllerRepresentable {
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

        // Enable folder picking on iOS 16+
        if #available(iOS 16.0, *) {
            picker.contentTypes = allowedContentTypes
        }

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
            // Handle security-scoped resource access for each URL
            var processedURLs: [URL] = []

            for url in urls {
                // Start accessing security-scoped resource
                let accessed = url.startAccessingSecurityScopedResource()

                if accessed {
                    // Keep the security-scoped access active
                    // The URL will need stopAccessingSecurityScopedResource() when done
                    processedURLs.append(url)
                } else {
                    // If we can't access, still add it - might work for local files
                    processedURLs.append(url)
                }
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

    /// Create a bookmark for persistent security-scoped access
    func createSecurityScopedBookmark() -> Data? {
        try? bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolve a security-scoped bookmark
    static func resolveSecurityScopedBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}