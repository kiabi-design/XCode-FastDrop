import Foundation
import Network

// MARK: - Errors

enum TransferError: LocalizedError {
    case connectionClosed
    case timeout
    case rejected
    case invalidHeader
    case notEnoughSpace
    case fileUnreadable(String)
    case diskError(String)

    var errorDescription: String? {
        switch self {
        case .connectionClosed: return "Соединение разорвано"
        case .timeout: return "Устройство не отвечает. Проверьте IP-адрес и Wi-Fi"
        case .rejected: return "Получатель отклонил передачу"
        case .invalidHeader: return "Некорректный запрос"
        case .notEnoughSpace: return "Недостаточно места на устройстве"
        case .fileUnreadable(let name): return "Не удалось прочитать файл \(name)"
        case .diskError(let message): return "Ошибка записи: \(message)"
        }
    }
}

/// Turns any error into a short Russian message for the UI.
func userMessage(for error: Error) -> String {
    if let transfer = error as? TransferError {
        return transfer.errorDescription ?? "Неизвестная ошибка"
    }
    if let nw = error as? NWError, case .posix(let code) = nw {
        switch code {
        case .ECONNREFUSED: return "Устройство отказало в соединении. Откройте FastDrop на получателе"
        case .EHOSTUNREACH, .ENETUNREACH: return "Устройство недоступно в этой сети"
        case .ECONNRESET, .EPIPE, .ECANCELED: return "Соединение разорвано"
        default: break
        }
    }
    return error.localizedDescription
}

// MARK: - One-shot guard

private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - Async wrapper over NWConnection

final class AsyncConnection: @unchecked Sendable {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "fastdrop.connection")

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    convenience init(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 14680
        )
        self.init(NWConnection(to: endpoint, using: AsyncConnection.tcpParameters()))
    }

    static func tcpParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        return NWParameters(tls: nil, tcp: tcp)
    }

    // MARK: Lifecycle

    /// Starts the connection and waits until it is ready.
    func start(timeout: TimeInterval = 8) async throws {
        let connection = self.connection
        let queue = self.queue

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let once = OneShot()

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if once.claim() {
                            connection.stateUpdateHandler = nil
                            continuation.resume()
                        }
                    case .failed(let error):
                        if once.claim() { continuation.resume(throwing: error) }
                    case .waiting(let error):
                        if case .posix(let code) = error,
                           code == .ECONNREFUSED || code == .EHOSTUNREACH || code == .ENETUNREACH {
                            if once.claim() {
                                connection.cancel()
                                continuation.resume(throwing: error)
                            }
                        }
                    case .cancelled:
                        if once.claim() { continuation.resume(throwing: CancellationError()) }
                    default:
                        break
                    }
                }

                queue.asyncAfter(deadline: .now() + timeout) {
                    if once.claim() {
                        connection.cancel()
                        continuation.resume(throwing: TransferError.timeout)
                    }
                }

                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func cancel() {
        connection.cancel()
    }

    // MARK: Raw I/O

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Returns between 1 and `maximum` bytes.
    func receiveChunk(maximum: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: TransferError.connectionClosed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    func receive(exactly count: Int) async throws -> Data {
        var buffer = Data()
        buffer.reserveCapacity(count)
        while buffer.count < count {
            buffer.append(try await receiveChunk(maximum: count - buffer.count))
        }
        return buffer
    }

    // MARK: Framing

    func sendHeader(_ header: FileHeader) async throws {
        let json = try JSONEncoder().encode(header)
        var length = UInt32(json.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(json)
        try await send(frame)
    }

    func receiveHeader() async throws -> FileHeader {
        let lengthBytes = try await receive(exactly: 4)
        let length = lengthBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= UInt32(NetworkConstants.maxHeaderSize) else {
            throw TransferError.invalidHeader
        }
        let json = try await receive(exactly: Int(length))
        guard let header = try? JSONDecoder().decode(FileHeader.self, from: json),
              header.version == NetworkConstants.protocolVersion,
              header.size >= 0
        else { throw TransferError.invalidHeader }
        return header
    }

    // MARK: Info

    /// IPv4 address of the remote side (available once the connection is ready).
    var remoteIPv4: String? {
        guard let endpoint = connection.currentPath?.remoteEndpoint,
              case .hostPort(let host, _) = endpoint,
              case .ipv4(let address) = host
        else { return nil }
        return "\(address)".components(separatedBy: "%").first
    }
}
