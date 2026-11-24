import UIKit

enum FileOpener {
    /// Opens the folder in the Files app (works for the app's Documents directory).
    static func revealFolder(containing path: String) {
        let folder = (path as NSString).deletingLastPathComponent
        openInFiles(folder)
    }

    static func openInFiles(_ path: String) {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "shareddocuments://" + encoded)
        else { return }
        UIApplication.shared.open(url)
    }
}
