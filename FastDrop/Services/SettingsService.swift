import Foundation
import SwiftUI

@MainActor
final class SettingsService: ObservableObject {
    static let shared = SettingsService()
    
    @AppStorage("isWhiteTheme") var isWhiteTheme: Bool = false
    @AppStorage("customSaveDirectory") var customSaveDirectory: String?
    @AppStorage("deviceName") var deviceName: String?
    @AppStorage("transferHistory") private var historyData: Data = Data()
    
    @Published var history: [TransferHistoryItem] = []
    
    private init() {
        loadHistory()
    }
    
    func loadHistory() {
        if let decoded = try? JSONDecoder().decode([TransferHistoryItem].self, from: historyData) {
            history = decoded
        }
    }
    
    func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            historyData = encoded
        }
    }
    
    func addHistoryItem(_ item: TransferHistoryItem) {
        history.insert(item, at: 0)
        if history.count > TransferHistoryItem.maxHistoryItems {
            history.removeLast()
        }
        saveHistory()
    }
    
    func clearHistory() {
        history.removeAll()
        saveHistory()
    }
    
    func clearHistory(direction: TransferDirection) {
        history.removeAll { $0.direction == direction }
        saveHistory()
    }
    
    var displayName: String {
        if let custom = deviceName, !custom.isEmpty { return custom }
        return UIDevice.current.name
    }
    
    func saveDirectory() -> URL {
        if let custom = customSaveDirectory, !custom.isEmpty {
            let url = URL(fileURLWithPath: custom)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("FastDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
