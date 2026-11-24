import Foundation
import Network
import Combine
import UIKit
import Darwin

/// Discovery (Bonjour), listening for incoming files and receiving them.
/// Sending lives in `FileSender`.
@MainActor
final class NetworkService: ObservableObject {
    static let shared = NetworkService()

    // MARK: Published state

    @Published private(set) var discoveredPeers: [DiscoveredPeer] = []
    @Published private(set) var myIPs: [String] = []
    @Published private(set) var isListening = false
    @Published private(set) var listenError: String?

    // MARK: Configuration & callbacks (always invoked on the main actor)

    var receiveEnabled = true
    var canAccept: (() -> Bool)?

    var onReceiveStart: ((FileHeader) -> Void)?
    var onReceiveProgress: ((Int64, Int64) -> Void)?
    var onReceiveComplete: ((URL, FileHeader) -> Void)?
    var onReceiveError: ((String) -> Void)?

    // MARK: Private

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var resolvers: [String: AsyncConnection] = [:]
    private var knownPeers: [String: DiscoveredPeer] = [:]
    private var receiveTasks: [UUID: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let instanceID = String(UUID().uuidString.prefix(8))
    private let queue = DispatchQueue(label: "fastdrop.network")

    private init() {
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.start() }
            .store(in: &cancellables)

        SettingsService.shared.$deviceName
            .dropFirst()
            .debounce(for: .seconds(0.6), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.start() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// (Re)starts advertising and browsing. Safe to call repeatedly.
    func start() {
        stop()
        listenError = nil
        refreshIPs()
        startListener()
        startBrowser()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers.removeAll()
        knownPeers.removeAll()
        discoveredPeers = []
        isListening = false
    }

    func cancelReceive() {
        receiveTasks.values.forEach { $0.cancel() }
    }

    func refreshIPs() {
        myIPs = Self.localIPv4Addresses()
    }

    // MARK: - Listener

    private var serviceName: String {
        let name = String(SettingsService.shared.displayName.prefix(40))
        return "\(name) #\(instanceID)"
    }

    private func startListener() {
        do {
            let params = AsyncConnection.tcpParameters()
            params.allowLocalEndpointReuse = true

            let port = NWEndpoint.Port(rawValue: NetworkConstants.transferPort) ?? 14680
            let listener = try NWListener(using: params, on: port)
            listener.service = NWListener.Service(name: serviceName, type: NetworkConstants.serviceType)

            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self = self, let listener = listener, self.listener === listener else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                        self.listenError = nil
                    case .waiting(let error), .failed(let error):
                        self.isListening = false
                        self.listenError = Self.describe(error)
                    case .cancelled:
                        self.isListening = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }

            self.listener = listener
            listener.start(queue: queue)
        } catch {
            isListening = false
            listenError = "Не удалось открыть порт \(NetworkConstants.transferPort)"
        }
    }

    private static func describe(_ error: NWError) -> String {
        if case .dns(let code) = error, code == -65570 {
            return "Нет доступа к локальной сети — разрешите в Настройках"
        }
        return error.localizedDescription
    }

    // MARK: - Browser

    private func startBrowser() {
        let browser = NWBrowser(
            for: .bonjour(type: NetworkConstants.serviceType, domain: nil),
            using: .tcp
        )

        browser.stateUpdateHandler = { [weak self, weak browser] state in
            Task { @MainActor in
                guard let self = self, let browser = browser, self.browser === browser else { return }
                switch state {
                case .waiting(let error), .failed(let error):
                    if self.listenError == nil { self.listenError = Self.describe(error) }
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            Task { @MainActor in
                guard let self = self, let browser = browser, self.browser === browser else { return }
                self.handleBrowse(results)
            }
        }

        self.browser = browser
        browser.start(queue: queue)
    }

    private func handleBrowse(_ results: Set<NWBrowser.Result>) {
        var present = Set<String>()

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            if name.hasSuffix("#\(instanceID)") { continue }   // that's us

            present.insert(name)
            if knownPeers[name] == nil && resolvers[name] == nil {
                resolve(name: name, endpoint: result.endpoint)
            }
        }

        for name in Array(knownPeers.keys) where !present.contains(name) {
            knownPeers[name] = nil
        }
        for (name, resolver) in resolvers where !present.contains(name) {
            resolver.cancel()
            resolvers[name] = nil
        }
        publishPeers()
    }

    /// Bonjour gives us a service, not an address — connect once to learn the peer's IPv4.
    private func resolve(name: String, endpoint: NWEndpoint) {
        let params = AsyncConnection.tcpParameters()
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = AsyncConnection(NWConnection(to: endpoint, using: params))
        resolvers[name] = connection

        Task { [weak self] in
            var address: String?
            do {
                try await connection.start(timeout: 6)
                address = connection.remoteIPv4
            } catch {
                address = nil
            }
            connection.cancel()
            self?.finishResolve(name: name, ip: address)
        }
    }

    private func finishResolve(name: String, ip: String?) {
        resolvers[name] = nil
        guard let ip = ip else { return }
        knownPeers[name] = DiscoveredPeer(id: name, ip: ip, name: Self.peerName(from: name), os: "iOS")
        publishPeers()
    }

    private func publishPeers() {
        discoveredPeers = knownPeers.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func peerName(from serviceName: String) -> String {
        if let range = serviceName.range(of: " #", options: .backwards) {
            return String(serviceName[..<range.lowerBound])
        }
        return serviceName
    }

    // MARK: - Receiving

    private func accept(_ nwConnection: NWConnection) {
        let id = UUID()
        let connection = AsyncConnection(nwConnection)

        receiveTasks[id] = Task { [weak self] in
            await self?.runReceive(connection)
            self?.receiveTasks[id] = nil
        }
    }

    nonisolated private func runReceive(_ conn: AsyncConnection) async {
        await withTaskCancellationHandler {
            await self.receiveOne(conn)
        } onCancel: {
            conn.cancel()
        }
    }

    nonisolated private func receiveOne(_ conn: AsyncConnection) async {
        defer { conn.cancel() }

        var handle: FileHandle?
        var partialURL: URL?
        var saveAccess: SaveAccess?
        var started = false
        defer { saveAccess?.release() }

        do {
            try await conn.start(timeout: 10)

            // Probes from other devices (address resolution) close without a header — stay silent.
            let header = try await conn.receiveHeader()

            let allowed = await MainActor.run {
                self.receiveEnabled && (self.canAccept?() ?? true)
            }
            guard allowed else {
                try? await conn.send(Data([0]))
                return
            }

            let access = await MainActor.run { SettingsService.shared.beginSaveAccess() }
            saveAccess = access

            if let free = (try? access.url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage,
               free < header.size {
                try? await conn.send(Data([0]))
                await MainActor.run { self.onReceiveError?(TransferError.notEnoughSpace.errorDescription ?? "") }
                return
            }

            let partial = access.url.appendingPathComponent(".\(UUID().uuidString).part")
            guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
                try? await conn.send(Data([0]))
                throw TransferError.diskError("не удалось создать файл")
            }
            partialURL = partial
            handle = try FileHandle(forWritingTo: partial)

            try await conn.send(Data([1]))

            started = true
            await MainActor.run { self.onReceiveStart?(header) }

            var received: Int64 = 0
            var lastReport = Date.distantPast

            while received < header.size {
                try Task.checkCancellation()

                let wanted = Int(min(Int64(NetworkConstants.chunkSize), header.size - received))
                let chunk = try await conn.receiveChunk(maximum: wanted)
                try handle?.write(contentsOf: chunk)
                received += Int64(chunk.count)

                let now = Date()
                if now.timeIntervalSince(lastReport) >= 0.1 || received == header.size {
                    lastReport = now
                    let current = received
                    Task { @MainActor in self.onReceiveProgress?(current, header.size) }
                }
            }

            try handle?.close()
            handle = nil

            let finalURL = Self.uniqueURL(in: access.url, name: Self.sanitize(header.name))
            try FileManager.default.moveItem(at: partial, to: finalURL)
            partialURL = nil

            try? await conn.send(Data([1]))
            await MainActor.run { self.onReceiveComplete?(finalURL, header) }
        } catch {
            try? handle?.close()
            if let partialURL = partialURL {
                try? FileManager.default.removeItem(at: partialURL)
            }
            guard started, !Task.isCancelled, !(error is CancellationError) else { return }
            let message = userMessage(for: error)
            await MainActor.run { self.onReceiveError?(message) }
        }
    }

    // MARK: - Helpers

    nonisolated private static func sanitize(_ name: String) -> String {
        var base = (name as NSString).lastPathComponent
        base = base
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty || base == "." || base == ".." { base = "file" }
        return base
    }

    nonisolated private static func uniqueURL(in directory: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var n = 1
        repeat {
            let newName = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    nonisolated static func localIPv4Addresses() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.hasPrefix("169.254"), !result.contains(ip) { result.append(ip) }
            }
        }
        return result
    }
}
