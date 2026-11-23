import Foundation
import SwiftUI

// MARK: - Transfer Direction
enum TransferDirection: String, Codable, CaseIterable {
    case sent = "Отправлено"
    case received = "Принято"
    
    var icon: String {
        switch self {
        case .sent: return "arrow.up.circle.fill"
        case .received: return "arrow.down.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .sent: return .green
        case .received: return .blue
        }
    }
}

// MARK: - Transfer History Item
struct TransferHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let sizeBytes: Int64
    let direction: TransferDirection
    let savedPath: String
    let timestamp: Date
    
    init(fileName: String, sizeBytes: Int64, direction: TransferDirection, savedPath: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.direction = direction
        self.savedPath = savedPath
        self.timestamp = timestamp
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Discovered Peer
struct DiscoveredPeer: Identifiable, Equatable {
    let id = UUID()
    let ip: String
    var name: String
    let os: String
    var lastSeen: Date
    
    var icon: String {
        switch os.lowercased() {
        case "iphone", "ios": return "iphone.gen3"
        case "android": return "iphone.gen3.radiowaves.left.and.right"
        case "macos", "mac": return "macbook"
        case "linux": return "laptopcomputer"
        case "windows": return "desktopcomputer"
        default: return "network"
        }
    }
}

// MARK: - Transfer Progress
struct TransferProgress: Equatable {
    var fileName: String = ""
    var currentIndex: Int = 0
    var totalCount: Int = 0
    var progress: Double = 0.0  // 0.0...1.0
    var speedMBps: Double = 0.0
    var transferredBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var etaText: String = "--:--"
    var statusText: String = "Подготовка..."
    var isCompleted: Bool = false
    var isCancelled: Bool = false
    var isError: Bool = false
    var savedFilePath: String?
    var savedFolderPath: String?
    var maxSpeedMBps: Double = 0.0
    var avgSpeedMBps: Double = 0.0
    var minSpeedMBps: Double = 0.0
    var startTime: Date = Date()
    
    var percentText: String {
        String(format: "%.1f%%", progress * 100)
    }
    
    var formattedTransferred: String {
        ByteCountFormatter.string(fromByteCount: transferredBytes, countStyle: .file)
    }
    
    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

// MARK: - App Settings
struct AppSettings: Codable {
    var isWhiteTheme: Bool = false
    var customSaveDirectory: String?
    var deviceName: String?
    var history: [TransferHistoryItem] = []
    
    static let maxHistoryItems = 100
}

// MARK: - Outgoing Item
struct OutgoingItem: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
    let sizeBytes: Int64
    
    init(url: URL) {
        self.url = url
        self.fileName = url.lastPathComponent
        self.sizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)) ?? 0
    }
}

// MARK: - Network Constants
enum NetworkConstants {
    static let transferPort: UInt16 = 14680
    static let discoveryPort: UInt16 = 14681
    static let chunkSize: Int = 1024 * 1024  // 1 MB
    static let serviceType = "_fastdrop._tcp"
    static let appVersion = "1.2"
}
