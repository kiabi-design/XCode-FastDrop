import Foundation
import SwiftUI
import Network
import UIKit

@MainActor
final class HomeViewModel: ObservableObject {
    // Network (mirrored from NetworkService)
    @Published var targetIP: String = ""
    @Published private(set) var discoveredPeers: [DiscoveredPeer] = []
    @Published private(set) var myIPs: [String] = []
    @Published private(set) var isListening: Bool = false
    @Published private(set) var listenError: String?
    @Published var receiveEnabled: Bool = true {
        didSet { network.receiveEnabled = receiveEnabled }
    }

    // Transfer
    @Published private(set) var transferProgress = TransferProgress()
    @Published private(set) var isTransferring: Bool = false
    @Published var showTransferScreen: Bool = false
    @Published var selectedItems: [OutgoingItem] = []

    // UI
    @Published var showSettings: Bool = false
    @Published var showHistory: Bool = false
    @Published var showFilePicker: Bool = false
    @Published var dropHover: Bool = false
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var showStatusCard: Bool = false

    let settings = SettingsService.shared

    private let network = NetworkService.shared
    private var meter = SpeedMeter()
    private var sendTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    init() {
        network.$discoveredPeers.assign(to: &$discoveredPeers)
        network.$myIPs.assign(to: &$myIPs)
        network.$isListening.assign(to: &$isListening)
        network.$listenError.assign(to: &$listenError)

        setupNetworkCallbacks()
        network.receiveEnabled = receiveEnabled
        network.start()
    }

    // MARK: - Derived

    var isTargetValid: Bool {
        IPv4Address(targetIP.trimmingCharacters(in: .whitespaces)) != nil
    }

    var canSend: Bool {
        !selectedItems.isEmpty && isTargetValid && !isTransferring
    }

    // MARK: - Callbacks

    private func setupNetworkCallbacks() {
        network.canAccept = { [weak self] in
            guard let self = self else { return true }
            // Don't accept incoming files while we're busy sending.
            return !(self.isTransferring && self.transferProgress.isSending)
        }
        network.onReceiveStart = { [weak self] header in self?.receiveStarted(header) }
        network.onReceiveProgress = { [weak self] current, total in self?.receiveProgressed(current: current, total: total) }
        network.onReceiveComplete = { [weak self] url, header in self?.receiveCompleted(url: url, header: header) }
        network.onReceiveError = { [weak self] message in self?.receiveFailed(message) }
    }

    // MARK: - File selection

    func pickFiles() {
        showFilePicker = true
    }

    func handleImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            addFiles(urls)
        }
    }

    func addFiles(_ urls: [URL]) {
        let existing = Set(selectedItems.map { $0.url })
        let items = urls
            .filter { !existing.contains($0) }
            .compactMap { OutgoingItem(url: $0) }
        guard !items.isEmpty else { return }
        selectedItems.append(contentsOf: items)
        HapticManager.selection()
    }

    func removeSelectedItem(_ item: OutgoingItem) {
        selectedItems.removeAll { $0.id == item.id }
    }

    func clearSelectedItems() {
        selectedItems.removeAll()
    }

    // MARK: - Sending

    func startSending() {
        guard canSend else { return }

        let host = targetIP.trimmingCharacters(in: .whitespaces)
        let items = selectedItems
        selectedItems = []

        meter.reset()
        var progress = TransferProgress()
        progress.isSending = true
        progress.fileName = items[0].fileName
        progress.currentIndex = 1
        progress.totalCount = items.count
        progress.totalBytes = items.reduce(0) { $0 + $1.sizeBytes }
        progress.statusText = "Подключение к \(host)…"
        transferProgress = progress

        isTransferring = true
        showTransferScreen = true

        let senderName = settings.displayName
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            await self?.performSend(items, host: host, senderName: senderName)
        }
    }

    private func performSend(_ items: [OutgoingItem], host: String, senderName: String) async {
        var completedBytes: Int64 = 0

        for (offset, item) in items.enumerated() {
            if Task.isCancelled { return }
            beginSendingFile(item, index: offset + 1)

            let base = completedBytes
            do {
                try await FileSender.send(
                    item,
                    to: host,
                    index: offset + 1,
                    count: items.count,
                    senderName: senderName
                ) { [weak self] sent in
                    Task { @MainActor in self?.sendProgressed(bytes: base + sent) }
                }

                settings.addHistoryItem(TransferHistoryItem(
                    fileName: item.fileName,
                    sizeBytes: item.sizeBytes,
                    direction: .sent,
                    savedPath: item.url.path
                ))
                completedBytes += item.sizeBytes
                sendProgressed(bytes: completedBytes)
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                sendFailed(error)
                return
            }
        }

        if !Task.isCancelled { sendFinished() }
    }

    private func beginSendingFile(_ item: OutgoingItem, index: Int) {
        var p = transferProgress
        p.fileName = item.fileName
        p.currentIndex = index
        p.statusText = "Отправка…"
        transferProgress = p
    }

    private func sendProgressed(bytes: Int64) {
        guard isTransferring, transferProgress.isSending,
              !transferProgress.isCompleted, !transferProgress.isError else { return }

        meter.update(bytes: bytes)
        var p = transferProgress
        p.transferredBytes = bytes
        p.progress = p.totalBytes > 0 ? min(1, Double(bytes) / Double(p.totalBytes)) : 0
        applySpeed(to: &p)
        transferProgress = p
    }

    private func sendFinished() {
        var p = transferProgress
        p.isCompleted = true
        p.progress = 1
        p.transferredBytes = p.totalBytes
        p.statusText = "Отправка завершена"
        p.avgSpeedMBps = meter.average
        p.maxSpeedMBps = max(meter.maximum, meter.average)
        p.minSpeedMBps = meter.minimum > 0 ? min(meter.minimum, meter.average) : meter.average
        p.etaText = "Готово"
        transferProgress = p
        isTransferring = false
        HapticManager.notification(.success)
        showStatus("Файлы отправлены")
    }

    private func sendFailed(_ error: Error) {
        let message = userMessage(for: error)
        var p = transferProgress
        p.isError = true
        p.statusText = message
        transferProgress = p
        isTransferring = false
        HapticManager.notification(.error)
        showStatus("Ошибка отправки: \(message)")
    }

    // MARK: - Receiving

    private func receiveStarted(_ header: FileHeader) {
        meter.reset()
        var p = TransferProgress()
        p.isSending = false
        p.fileName = header.name
        p.currentIndex = header.index
        p.totalCount = header.count
        p.totalBytes = header.size
        p.statusText = "Приём от \(header.sender)…"
        transferProgress = p
        isTransferring = true
        showTransferScreen = true
        HapticManager.impact(.medium)
    }

    private func receiveProgressed(current: Int64, total: Int64) {
        guard isTransferring, !transferProgress.isSending,
              !transferProgress.isCompleted, !transferProgress.isError else { return }

        meter.update(bytes: current)
        var p = transferProgress
        p.transferredBytes = current
        p.totalBytes = total
        p.progress = total > 0 ? min(1, Double(current) / Double(total)) : 0
        applySpeed(to: &p)
        transferProgress = p
    }

    private func receiveCompleted(url: URL, header: FileHeader) {
        settings.addHistoryItem(TransferHistoryItem(
            fileName: url.lastPathComponent,
            sizeBytes: header.size,
            direction: .received,
            savedPath: url.path
        ))

        var p = transferProgress
        p.isCompleted = true
        p.progress = 1
        p.transferredBytes = header.size
        p.totalBytes = header.size
        p.savedFilePath = url.path
        p.fileName = url.lastPathComponent
        p.statusText = "Файл принят"
        p.avgSpeedMBps = meter.average
        p.maxSpeedMBps = max(meter.maximum, meter.average)
        p.minSpeedMBps = meter.minimum > 0 ? min(meter.minimum, meter.average) : meter.average
        p.etaText = "Готово"
        transferProgress = p
        isTransferring = false
        HapticManager.notification(.success)
        showStatus("Файл сохранён: \(url.lastPathComponent)")
    }

    private func receiveFailed(_ message: String) {
        if showTransferScreen && !transferProgress.isSending {
            var p = transferProgress
            p.isError = true
            p.statusText = message
            transferProgress = p
            isTransferring = false
            HapticManager.notification(.error)
        }
        showStatus("Ошибка приёма: \(message)")
    }

    // MARK: - Screen actions

    func cancelTransfer() {
        sendTask?.cancel()
        sendTask = nil
        network.cancelReceive()
        resetTransferUI()
    }

    func doneTransfer() {
        resetTransferUI()
    }

    func sendMore() {
        resetTransferUI()
        pickFiles()
    }

    private func resetTransferUI() {
        isTransferring = false
        showTransferScreen = false
        transferProgress = TransferProgress()
    }

    func openReceivedFolder() {
        if let path = transferProgress.savedFilePath {
            FileOpener.revealFolder(containing: path)
        } else {
            FileOpener.openInFiles(settings.defaultSaveDirectory().path)
        }
    }

    func copyIPToClipboard(_ ip: String) {
        UIPasteboard.general.string = ip
        HapticManager.notification(.success)
        showStatus("IP скопирован: \(ip)")
    }

    func refreshNetwork() {
        network.start()
    }

    // MARK: - Helpers

    private func applySpeed(to p: inout TransferProgress) {
        p.speedMBps = meter.current
        p.maxSpeedMBps = meter.maximum
        p.minSpeedMBps = meter.minimum
        p.avgSpeedMBps = meter.average

        let rate = meter.current > 0 ? meter.current : meter.average
        if rate > 0 {
            let remainingMB = Double(max(p.totalBytes - p.transferredBytes, 0)) / 1_048_576
            p.etaText = formatETA(Int(remainingMB / rate))
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        showStatusCard = true
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.showStatusCard = false
        }
    }

    private func formatETA(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)с" }
        let mins = seconds / 60
        let secs = seconds % 60
        if mins < 60 { return String(format: "%d:%02d", mins, secs) }
        return String(format: "%d:%02d:%02d", mins / 60, mins % 60, secs)
    }
}
