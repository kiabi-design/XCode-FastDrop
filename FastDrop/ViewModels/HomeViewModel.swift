import Foundation
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

@MainActor
final class HomeViewModel: ObservableObject {
    // Network
    @Published var targetIP: String = ""
    @Published var discoveredPeers: [DiscoveredPeer] = []
    @Published var myIPs: [String] = []
    @Published var isListening: Bool = false
    @Published var listenError: String?
    @Published var receiveEnabled: Bool = true {
        didSet { NetworkService.shared.receiveEnabled = receiveEnabled }
    }
    
    // Transfer
    @Published var transferProgress = TransferProgress()
    @Published var isTransferring: Bool = false
    @Published var showTransferScreen: Bool = false
    @Published var selectedItems: [OutgoingItem] = []
    
    // UI
    @Published var showSettings: Bool = false
    @Published var showHistory: Bool = false
    @Published var showFilePicker: Bool = false
    @Published var dropHover: Bool = false
    @Published var statusMessage: String = "Готово · v\(NetworkConstants.appVersion)"
    @Published var showStatusCard: Bool = false
    
    // Settings reference
    let settings = SettingsService.shared
    
    private var networkService = NetworkService.shared
    
    init() {
        setupNetworkCallbacks()
        Task { await networkService.start() }
        observeNetworkState()
    }
    
    deinit {
        networkService.stop()
    }
    
    private func setupNetworkCallbacks() {
        networkService.onReceiveStart = { [weak self] fileName, size in
            self?.startReceivingUI(fileName: fileName, size: size)
        }
        networkService.onReceiveProgress = { [weak self] current, total in
            self?.updateReceiveProgress(current: current, total: total)
        }
        networkService.onReceiveComplete = { [weak self] url in
            self?.completeReceiving(url: url)
        }
        networkService.onReceiveError = { [weak self] error in
            self?.receiveError(error)
        }
        networkService.onSendProgress = { [weak self] current, total in
            self?.updateSendProgress(current: current, total: total)
        }
        networkService.onSendComplete = { [weak self] in
            self?.completeSending()
        }
        networkService.onSendError = { [weak self] error in
            self?.sendError(error)
        }
    }
    
    private func observeNetworkState() {
        // Observe network service published properties
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.discoveredPeers = self.networkService.discoveredPeers
                self.myIPs = self.networkService.myIPs
                self.isListening = self.networkService.isListening
                self.listenError = self.networkService.listenError
            }
        }
    }
    
    // MARK: - Actions
    
    func pickFiles() {
        showFilePicker = true
    }
    
    func handleDroppedFiles(_ urls: [URL]) {
        let items = urls.map(OutgoingItem.init)
        selectedItems.append(contentsOf: items)
        if !kSendImmediately {
            startSending()
        }
    }
    
    func removeSelectedItem(_ item: OutgoingItem) {
        selectedItems.removeAll { $0.id == item.id }
    }
    
    func clearSelectedItems() {
        selectedItems.removeAll()
    }
    
    func startSending() {
        guard !selectedItems.isEmpty, !targetIP.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let items = selectedItems
        selectedItems.removeAll()
        
        isTransferring = true
        showTransferScreen = true
        
        resetTransferProgress()
        transferProgress.fileName = items.first?.fileName ?? ""
        transferProgress.currentIndex = 1
        transferProgress.totalCount = items.count
        transferProgress.statusText = "Подключение к \(targetIP)..."
        
        Task {
            await networkService.sendFiles(items, to: targetIP.trimmingCharacters(in: .whitespaces))
        }
    }
    
    func cancelTransfer() {
        if transferProgress.isCompleted { return }
        networkService.cancelSend()
        networkService.cancelReceive()
        resetTransferUI()
    }
    
    func doneTransfer() {
        showTransferScreen = false
        resetTransferUI()
    }
    
    func sendMore() {
        showTransferScreen = false
        resetTransferUI()
        pickFiles()
    }
    
    func openReceivedFile(_ url: URL) {
        // Open with system
        UIApplication.shared.open(url)
    }
    
    func openReceivedFolder() {
        let folder = settings.saveDirectory()
        UIApplication.shared.open(folder)
    }
    
    func copyIPToClipboard(_ ip: String) {
        UIPasteboard.general.string = ip
        showStatus("IP скопирован: \(ip)")
    }
    
    func refreshNetwork() {
        Task {
            await networkService.start()
        }
    }
    
    // MARK: - Transfer UI Helpers
    
    private func resetTransferProgress() {
        transferProgress = TransferProgress()
        transferProgress.maxSpeedMBps = 0
        transferProgress.avgSpeedMBps = 0
        transferProgress.minSpeedMBps = 0
    }
    
    private func resetTransferUI() {
        isTransferring = false
        transferProgress = TransferProgress()
    }
    
    private func startReceivingUI(fileName: String, size: Int64) {
        isTransferring = true
        showTransferScreen = true
        resetTransferProgress()
        transferProgress.fileName = fileName
        transferProgress.totalBytes = size
        transferProgress.statusText = "Приём \(fileName)..."
    }
    
    private func updateReceiveProgress(current: Int64, total: Int64) {
        transferProgress.transferredBytes = current
        transferProgress.totalBytes = total
        transferProgress.progress = total > 0 ? Double(current) / Double(total) : 0
        
        let elapsed = Date().timeIntervalSinceReferenceDate - (transferProgress.startTime?.timeIntervalSinceReferenceDate ?? Date().timeIntervalSinceReferenceDate)
        if elapsed > 0 {
            transferProgress.speedMBps = Double(current) / (1024*1024) / elapsed
            transferProgress.maxSpeedMBps = max(transferProgress.maxSpeedMBps, transferProgress.speedMBps)
            transferProgress.minSpeedMBps = transferProgress.minSpeedMBps == 0 ? transferProgress.speedMBps : min(transferProgress.minSpeedMBps, transferProgress.speedMBps)
            
            let remaining = total - current
            if transferProgress.speedMBps > 0 {
                let eta = remaining / Int64(transferProgress.speedMBps * 1024 * 1024)
                transferProgress.etaText = formatETA(eta)
            }
        }
    }
    
    private func completeReceiving(url: URL) {
        transferProgress.isCompleted = true
        transferProgress.progress = 1.0
        transferProgress.transferredBytes = transferProgress.totalBytes
        transferProgress.savedFilePath = url.path
        transferProgress.savedFolderPath = url.deletingLastPathComponent().path
        transferProgress.statusText = "Файл принят"
        transferProgress.avgSpeedMBps = transferProgress.maxSpeedMBps // simplify
        
        showStatus("Файл сохранён: \(url.lastPathComponent)")
    }
    
    private func receiveError(_ error: String) {
        transferProgress.isError = true
        transferProgress.statusText = "Ошибка: \(error)"
        isTransferring = false
        showStatus("Ошибка приёма: \(error)")
    }
    
    private func updateSendProgress(current: Int64, total: Int64) {
        transferProgress.transferredBytes = current
        transferProgress.totalBytes = total
        transferProgress.progress = total > 0 ? Double(current) / Double(total) : 0
        
        // Speed calculation handled in network service
    }
    
    private func completeSending() {
        transferProgress.isCompleted = true
        transferProgress.progress = 1.0
        transferProgress.transferredBytes = transferProgress.totalBytes
        transferProgress.statusText = "Отправка завершена"
        isTransferring = false
        showStatus("Файлы отправлены")
    }
    
    private func sendError(_ error: String) {
        transferProgress.isError = true
        transferProgress.statusText = "Ошибка: \(error)"
        isTransferring = false
        showStatus("Ошибка отправки: \(error)")
    }
    
    private func showStatus(_ message: String) {
        statusMessage = message
        showStatusCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showStatusCard = false
        }
    }
    
    private func formatETA(_ seconds: Int64) -> String {
        if seconds < 60 { return "\(seconds)с" }
        let mins = seconds / 60
        let secs = seconds % 60
        if mins < 60 { return String(format: "%d:%02d", mins, secs) }
        let hours = mins / 60
        let remMins = mins % 60
        return String(format: "%d:%02d:%02d", hours, remMins, secs)
    }
}

// MARK: - Constants
private let kSendImmediately = false
