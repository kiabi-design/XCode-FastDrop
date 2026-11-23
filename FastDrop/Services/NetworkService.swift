import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.fastdrop", category: "Network")

// MARK: - Network Service
@MainActor
final class NetworkService: ObservableObject {
    static let shared = NetworkService()

    // Published state
    @Published var discoveredPeers: [DiscoveredPeer] = []
    @Published var myIPs: [String] = []
    @Published var isListening: Bool = false
    @Published var listenError: String?
    @Published var receiveEnabled: Bool = true {
        didSet {
            if receiveEnabled {
                Task { await startReceiving() }
            } else {
                stopReceiving()
            }
        }
    }

    // Callbacks
    var onReceiveStart: ((String, Int64) -> Void)?
    var onReceiveProgress: ((Int64, Int64) -> Void)?
    var onReceiveComplete: ((URL) -> Void)?
    var onReceiveError: ((String) -> Void)?
    var onSendProgress: ((Int64, Int64) -> Void)?
    var onSendComplete: (() -> Void)?
    var onSendError: ((String) -> Void)?

    // Network
    private var tcpListener: NWListener?
    private var udpConnection: NWConnection?
    private var beaconTimer: Timer?
    private var cleanupTimer: Timer?
    private let queue = DispatchQueue(label: "com.fastdrop.network", qos: .userInitiated)
    private let peerQueue = DispatchQueue(label: "com.fastdrop.peers", qos: .utility)

    // Transfer state
    private var activeReceiveFile: URL?
    private var activeReceiveHandle: FileHandle?
    private var expectedReceiveSize: Int64 = 0
    private var receivedBytes: Int64 = 0
    private var shouldCancelReceive = false
    private var activeSendCancellation = false

    private init() {}

    // MARK: - Public API

    func start() async {
        await refreshLocalIPs()
        await startUDPDiscovery()

        if receiveEnabled {
            await startReceiving()
        }
    }

    func stop() {
        stopAll()
    }

    func sendFiles(_ items: [OutgoingItem], to ip: String) async {
        activeSendCancellation = false
        await performSend(items: items, targetIP: ip)
    }

    func cancelSend() {
        activeSendCancellation = true
    }

    func cancelReceive() {
        shouldCancelReceive = true
        cleanupReceive()
    }

    // MARK: - Local IPs

    private func refreshLocalIPs() async {
        var ips: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return
        }

        defer {
            freeifaddrs(ifaddr)
        }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee

            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: interface.ifa_name)

            if name.hasPrefix("lo") ||
                name.hasPrefix("utun") ||
                name.hasPrefix("awdl") {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            let ip = String(cString: hostname)

            if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                ips.append(ip)
            }
        }

        await MainActor.run {
            self.myIPs = ips.sorted()
        }
    }

    // MARK: - UDP Discovery

    private func startUDPDiscovery() async {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true

        udpConnection = NWConnection(
            host: "255.255.255.255",
            port: NWEndpoint.Port(rawValue: NetworkConstants.discoveryPort)!,
            using: params
        )

        udpConnection?.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                Task { @MainActor in
                    self?.startBeacon()
                    self?.startReceivingBeacons()
                }
            }
        }

        udpConnection?.start(queue: queue)
    }

    private func startBeacon() {
        beaconTimer?.invalidate()

        beaconTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sendBeacon()
            }
        }

        beaconTimer?.fire()
    }

    private func sendBeacon() {
        let settings = SettingsService.shared

        let payload = """
        {
            "name": "\(settings.displayName)",
            "os": "iOS",
            "version": "\(NetworkConstants.appVersion)"
        }
        """

        let data = payload.data(using: .utf8)!

        udpConnection?.send(
            content: data,
            completion: .contentProcessed { error in
                if let error = error {
                    logger.error("Beacon send error: \(error)")
                }
            }
        )
    }

    private func startReceivingBeacons() {
        udpConnection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, _ in
            Task { @MainActor in
                if let data = data, !data.isEmpty {
                    self?.processBeacon(data)
                }

                if !isComplete {
                    self?.startReceivingBeacons()
                }
            }
        }
    }

    private func processBeacon(_ data: Data) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let _ = json["name"],
            let _ = json["os"]
        else {
            return
        }

        peerQueue.async { [weak self] in
            guard self != nil else {
                return
            }
        }
    }

    // MARK: - TCP Receiving (File Transfer Server)

    private func startReceiving() async {
        guard tcpListener == nil else {
            return
        }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true

            tcpListener = try NWListener(
                using: params,
                on: NWEndpoint.Port(rawValue: NetworkConstants.transferPort)!
            )

            tcpListener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleIncomingConnection(connection)
                }
            }

            tcpListener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isListening = true
                        self?.listenError = nil

                    case .failed(let error):
                        self?.isListening = false
                        self?.listenError = error.localizedDescription

                    case .cancelled:
                        self?.isListening = false

                    default:
                        break
                    }
                }
            }

            tcpListener?.start(queue: queue)

            // Periodic cleanup of stale peers
            cleanupTimer = Timer.scheduledTimer(
                withTimeInterval: 10,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.cleanupStalePeers()
                }
            }

        } catch {
            await MainActor.run {
                self.listenError = error.localizedDescription
            }

            logger.error("Failed to start TCP listener: \(error)")
        }
    }

    private func stopReceiving() {
        tcpListener?.cancel()
        tcpListener = nil

        cleanupTimer?.invalidate()
        cleanupTimer = nil

        Task { @MainActor in
            self.isListening = false
        }
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeader(connection)
    }

    private func receiveHeader(_ connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 8,
            maximumLength: 8
        ) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard
                    let self = self,
                    let data = data,
                    data.count == 8,
                    !isComplete
                else {
                    if let error = error {
                        logger.error("Header receive error: \(error)")
                    }

                    connection.cancel()
                    return
                }

                let fileNameLength = Int(
                    data.withUnsafeBytes {
                        $0.load(as: UInt32.self)
                    }.littleEndian
                )

                let fileSize = Int64(
                    data.advanced(by: 4).withUnsafeBytes {
                        $0.load(as: UInt64.self)
                    }.littleEndian
                )

                self.receiveFileName(
                    connection,
                    length: fileNameLength,
                    fileSize: fileSize
                )
            }
        }
    }

    private func receiveFileName(
        _ connection: NWConnection,
        length: Int,
        fileSize: Int64
    ) {
        connection.receive(
            minimumIncompleteLength: length,
            maximumLength: length
        ) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard
                    let self = self,
                    let data = data,
                    data.count == length,
                    !isComplete,
                    let fileName = String(data: data, encoding: .utf8)
                else {
                    if let error = error {
                        logger.error("Filename receive error: \(error)")
                    }

                    connection.cancel()
                    return
                }

                self.startFileReceive(
                    connection,
                    fileName: fileName,
                    fileSize: fileSize
                )
            }
        }
    }

    private func startFileReceive(
        _ connection: NWConnection,
        fileName: String,
        fileSize: Int64
    ) {
        let saveDir = SettingsService.shared.saveDirectory()
        let destinationURL = saveDir.appendingPathComponent(fileName)

        // Handle duplicate names
        var finalURL = destinationURL
        var counter = 1

        while FileManager.default.fileExists(atPath: finalURL.path) {
            let ext = destinationURL.pathExtension
            let name = destinationURL.deletingPathExtension().lastPathComponent

            let newName = ext.isEmpty
                ? "\(name) (\(counter))"
                : "\(name) (\(counter)).\(ext)"

            finalURL = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(newName)

            counter += 1
        }

        self.activeReceiveFile = finalURL
        self.expectedReceiveSize = fileSize
        self.receivedBytes = 0
        self.shouldCancelReceive = false

        // Create file
        FileManager.default.createFile(
            atPath: finalURL.path,
            contents: nil
        )

        do {
            self.activeReceiveHandle = try FileHandle(
                forWritingTo: finalURL
            )
        } catch {
            logger.error("Failed to create file handle: \(error)")

            self.onReceiveError?(
                "Не удалось создать файл: \(error.localizedDescription)"
            )

            connection.cancel()
            return
        }

        self.onReceiveStart?(fileName, fileSize)
        receiveFileData(connection)
    }

    private func receiveFileData(_ connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: NetworkConstants.chunkSize
        ) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else {
                    return
                }

                if let data = data, !data.isEmpty {
                    if self.shouldCancelReceive {
                        connection.cancel()
                        self.cleanupReceive()
                        return
                    }

                    do {
                        try self.activeReceiveHandle?.write(contentsOf: data)
                        self.receivedBytes += Int64(data.count)

                        self.onReceiveProgress?(
                            self.receivedBytes,
                            self.expectedReceiveSize
                        )
                    } catch {
                        logger.error("Write error: \(error)")

                        self.onReceiveError?(
                            "Ошибка записи: \(error.localizedDescription)"
                        )

                        connection.cancel()
                        self.cleanupReceive()
                        return
                    }
                }

                if isComplete ||
                    self.receivedBytes >= self.expectedReceiveSize ||
                    self.shouldCancelReceive {

                    if !self.shouldCancelReceive &&
                        self.receivedBytes >= self.expectedReceiveSize {

                        self.activeReceiveHandle?.closeFile()

                        if let url = self.activeReceiveFile {
                            self.onReceiveComplete?(url)

                            SettingsService.shared.addHistoryItem(
                                TransferHistoryItem(
                                    fileName: url.lastPathComponent,
                                    sizeBytes: self.expectedReceiveSize,
                                    direction: .received,
                                    savedPath: url.path
                                )
                            )
                        }
                    } else if self.shouldCancelReceive {
                        self.cleanupReceive()
                    }

                    connection.cancel()
                    return
                }

                if let error = error {
                    logger.error("Receive data error: \(error)")
                    self.onReceiveError?(error.localizedDescription)

                    connection.cancel()
                    self.cleanupReceive()
                    return
                }

                self.receiveFileData(connection)
            }
        }
    }

    private func cleanupReceive() {
        activeReceiveHandle?.closeFile()
        activeReceiveHandle = nil

        if let url = activeReceiveFile, shouldCancelReceive {
            try? FileManager.default.removeItem(at: url)
        }

        activeReceiveFile = nil
        expectedReceiveSize = 0
        receivedBytes = 0
        shouldCancelReceive = false
    }

    // MARK: - TCP Sending (File Transfer Client)

    private func performSend(
        items: [OutgoingItem],
        targetIP: String
    ) async {
        for (index, item) in items.enumerated() {
            if activeSendCancellation {
                break
            }

            await sendSingleFile(
                item,
                index: index + 1,
                total: items.count,
                targetIP: targetIP
            )
        }

        if !activeSendCancellation {
            self.onSendComplete?()
        }
    }

    private func sendSingleFile(
        _ item: OutgoingItem,
        index: Int,
        total: Int,
        targetIP: String
    ) async {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(targetIP),
                port: NWEndpoint.Port(rawValue: NetworkConstants.transferPort)!,
                using: .tcp
            )

            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    Task { @MainActor in
                        guard let self = self else {
                            continuation.resume()
                            return
                        }
                        self.sendFileData(
                            connection,
                            item: item,
                            index: index,
                            total: total,
                            continuation: continuation
                        )
                    }

                case .failed(let error):
                    logger.error("Send connection failed: \(error)")
                    Task { @MainActor in
                        self?.onSendError?(
                            "Ошибка подключения: \(error.localizedDescription)"
                        )
                    }
                    continuation.resume()

                case .cancelled:
                    continuation.resume()

                default:
                    break
                }
            }

            connection.start(queue: self.queue)
        }
    }

    private func sendFileData(
        _ connection: NWConnection,
        item: OutgoingItem,
        index: Int,
        total: Int,
        continuation: CheckedContinuation<Void, Never>
    ) {
        let fileNameData = item.fileName.data(using: .utf8)!
        let fileNameLength = UInt32(fileNameData.count).littleEndian
        let fileSize = UInt64(item.sizeBytes).littleEndian

        var header = Data()

        header.append(
            withUnsafeBytes(of: fileNameLength) {
                Data($0)
            }
        )

        header.append(
            withUnsafeBytes(of: fileSize) {
                Data($0)
            }
        )

        header.append(fileNameData)

        connection.send(
            content: header,
            completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    if let error = error {
                        logger.error("Header send error: \(error)")

                        self?.onSendError?(
                            "Ошибка отправки заголовка: \(error.localizedDescription)"
                        )

                        connection.cancel()
                        continuation.resume()
                        return
                    }

                    self?.streamFile(
                        connection,
                        url: item.url,
                        item: item,
                        continuation: continuation
                    )
                }
            }
        )
    }

    private func streamFile(
        _ connection: NWConnection,
        url: URL,
        item: OutgoingItem,
        continuation: CheckedContinuation<Void, Never>
    ) {
        var sentBytes: Int64 = 0
        var lastProgressTime = Date()
        var speeds: [Double] = []

        func sendNextChunk() {
            if self.activeSendCancellation {
                connection.cancel()
                continuation.resume()
                return
            }

            let
