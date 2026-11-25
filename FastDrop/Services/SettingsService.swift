import Foundation
import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A writable folder that may need security-scoped access for the duration of a transfer.
struct SaveAccess {
    let url: URL
    private let stop: () -> Void

    init(url: URL, stop: @escaping () -> Void = {}) {
        self.url = url
        self.stop = stop
    }

    func release() { stop() }
}

@MainActor
final class SettingsService: ObservableObject {
    static let shared = SettingsService()
    static let maxHistoryItems = 100

    private enum Keys {
        static let appearance = "appearanceMode"
        static let deviceName = "deviceName"
        static let history = "transferHistory"
        static let saveBookmark = "saveFolderBookmark"
        static let saveFolderName = "saveFolderName"
    }

    private let defaults = UserDefaults.standard

    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    @Published var deviceName: String? {
        didSet { defaults.set(deviceName, forKey: Keys.deviceName) }
    }

    @Published private(set) var saveFolderName: String?
    @Published private(set) var history: [TransferHistoryItem]

    private init() {
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        deviceName = defaults.string(forKey: Keys.deviceName)
        saveFolderName = defaults.string(forKey: Keys.saveFolderName)

        if let data = defaults.data(forKey: Keys.history),
           let decoded = try? JSONDecoder().decode([TransferHistoryItem].self, from: data) {
            history = decoded
        } else {
            history = []
        }
    }

    // MARK: - Device name

    var displayName: String {
        if let custom = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return UIDevice.current.name
    }

    // MARK: - History

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Keys.history)
        }
    }

    func addHistoryItem(_ item: TransferHistoryItem) {
        history.insert(item, at: 0)
        if history.count > Self.maxHistoryItems {
            history.removeLast(history.count - Self.maxHistoryItems)
        }
        persistHistory()
    }

    func removeHistoryItem(id: UUID) {
        history.removeAll { $0.id == id }
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    func clearHistory(direction: TransferDirection) {
        history.removeAll { $0.direction == direction }
        persistHistory()
    }

    // MARK: - Save folder

    var saveFolderDescription: String {
        saveFolderName ?? "Documents/FastDrop"
    }

    var usesCustomSaveFolder: Bool {
        defaults.data(forKey: Keys.saveBookmark) != nil
    }

    /// Remembers a folder picked via the document picker (security-scoped bookmark).
    func setSaveFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return
        }
        defaults.set(data, forKey: Keys.saveBookmark)
        defaults.set(url.lastPathComponent, forKey: Keys.saveFolderName)
        saveFolderName = url.lastPathComponent
    }

    func resetSaveFolder() {
        defaults.removeObject(forKey: Keys.saveBookmark)
        defaults.removeObject(forKey: Keys.saveFolderName)
        saveFolderName = nil
    }

    /// Resolves the folder where incoming files are written. Call `release()` when done.
    func beginSaveAccess() -> SaveAccess {
        if let data = defaults.data(forKey: Keys.saveBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                let scoped = url.startAccessingSecurityScopedResource()
                if FileManager.default.fileExists(atPath: url.path) {
                    if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                        defaults.set(fresh, forKey: Keys.saveBookmark)
                    }
                    return SaveAccess(url: url) {
                        if scoped { url.stopAccessingSecurityScopedResource() }
                    }
                }
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
        return SaveAccess(url: defaultSaveDirectory())
    }

    func defaultSaveDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("FastDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
