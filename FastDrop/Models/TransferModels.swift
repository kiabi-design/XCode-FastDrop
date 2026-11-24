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

    init(
        id: UUID = UUID(),
        fileName: String,
        sizeBytes: Int64,
        direction: TransferDirection,
        savedPath: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.direction = direction
        self.savedPath = savedPath
        self.timestamp = timestamp
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var formattedDate: String {
        Self.dateFormatter.string(from: timestamp)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm"
        return formatter
    }()
}

// MARK: - Discovered Peer

struct DiscoveredPeer: Identifiable, Equatable, Hashable {
    /// Bonjour service name — unique per running instance.
    let id: String
    var ip: String
    var name: String
    var os: String

    var icon: String {
        switch os.lowercased() {
        case "iphone", "ios": return "iphone"
        case "android": return "iphone.radiowaves.left.and.right"
        case "macos", "mac": return "macbook"
        case "linux": return "laptopcomputer"
        case "windows": return "desktopcomputer"
        default: return "network"
        }
    }
}

// MARK: - Transfer Progress

struct TransferProgress: Equatable {
    var isSending: Bool = true
    var fileName: String = ""
    var currentIndex: Int = 0
    var totalCount: Int = 0
    var progress: Double = 0.0            // 0.0...1.0
    var speedMBps: Double = 0.0
    var transferredBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var etaText: String = "--:--"
    var statusText: String = "Подготовка…"
    var isCompleted: Bool = false
    var isError: Bool = false
    var savedFilePath: String?
    var maxSpeedMBps: Double = 0.0
    var avgSpeedMBps: Double = 0.0
    var minSpeedMBps: Double = 0.0

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

// MARK: - Speed Meter

/// Smoothed throughput meter. Feed it the *total* number of bytes transferred so far.
struct SpeedMeter {
    private(set) var current: Double = 0   // MB/s, smoothed
    private(set) var maximum: Double = 0
    private(set) var minimum: Double = 0
    private(set) var average: Double = 0

    private var startTime = Date()
    private var lastTime = Date()
    private var lastBytes: Int64 = 0

    mutating func reset() {
        self = SpeedMeter()
    }

    mutating func update(bytes: Int64, now: Date = Date()) {
        let totalElapsed = now.timeIntervalSince(startTime)
        if totalElapsed > 0 {
            average = Double(bytes) / 1_048_576 / totalElapsed
        }

        let delta = now.timeIntervalSince(lastTime)
        guard delta >= 0.25 else { return }

        let instant = Double(bytes - lastBytes) / 1_048_576 / delta
        current = current == 0 ? instant : current * 0.6 + instant * 0.4
        maximum = Swift.max(maximum, current)
        if current > 0 {
            minimum = minimum == 0 ? current : Swift.min(minimum, current)
        }
        lastTime = now
        lastBytes = bytes
    }
}

// MARK: - Outgoing Item

struct OutgoingItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let fileName: String
    let sizeBytes: Int64

    /// Returns nil for folders and unreadable URLs.
    init?(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
              values.isDirectory != true
        else { return nil }

        self.url = url
        self.fileName = url.lastPathComponent
        self.sizeBytes = Int64(values.fileSize ?? 0)
    }
}

// MARK: - Wire Protocol

/// Sent by the sender as: [UInt32 big-endian length][JSON FileHeader].
/// Receiver answers with one byte (1 = accept, 0 = reject), then the sender streams
/// exactly `size` raw bytes, and the receiver finishes with one byte (1 = saved OK).
struct FileHeader: Codable {
    let version: Int
    let name: String
    let size: Int64
    let index: Int
    let count: Int
    let sender: String
}

// MARK: - Network Constants

enum NetworkConstants {
    static let transferPort: UInt16 = 14680
    static let chunkSize: Int = 1024 * 1024          // 1 MB
    static let serviceType = "_fastdrop._tcp"        // must match NSBonjourServices in Info.plist
    static let protocolVersion = 1
    static let maxHeaderSize = 64 * 1024

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3"
    }
}
