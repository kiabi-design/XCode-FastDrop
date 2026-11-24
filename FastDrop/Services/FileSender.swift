import Foundation

enum FileSender {
    /// Sends one file. Throws on failure; cancel by cancelling the surrounding Task.
    /// `progress` receives the number of bytes of *this file* sent so far (throttled).
    static func send(
        _ item: OutgoingItem,
        to host: String,
        index: Int,
        count: Int,
        senderName: String,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let conn = AsyncConnection(host: host, port: NetworkConstants.transferPort)

        try await withTaskCancellationHandler {
            defer { conn.cancel() }

            let scoped = item.url.startAccessingSecurityScopedResource()
            defer { if scoped { item.url.stopAccessingSecurityScopedResource() } }

            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: item.url)
            } catch {
                throw TransferError.fileUnreadable(item.fileName)
            }
            defer { try? handle.close() }

            try await conn.start(timeout: 8)

            try await conn.sendHeader(FileHeader(
                version: NetworkConstants.protocolVersion,
                name: item.fileName,
                size: item.sizeBytes,
                index: index,
                count: count,
                sender: senderName
            ))

            let reply = try await conn.receive(exactly: 1)
            guard reply.first == 1 else { throw TransferError.rejected }

            var sent: Int64 = 0
            var lastReport = Date.distantPast

            while sent < item.sizeBytes {
                try Task.checkCancellation()

                let wanted = Int(min(Int64(NetworkConstants.chunkSize), item.sizeBytes - sent))
                guard let data = try handle.read(upToCount: wanted), !data.isEmpty else {
                    throw TransferError.fileUnreadable(item.fileName)
                }
                try await conn.send(data)
                sent += Int64(data.count)

                let now = Date()
                if now.timeIntervalSince(lastReport) >= 0.1 {
                    lastReport = now
                    progress(sent)
                }
            }

            progress(item.sizeBytes)

            let ack = try await conn.receive(exactly: 1)
            guard ack.first == 1 else { throw TransferError.connectionClosed }
        } onCancel: {
            conn.cancel()
        }
    }
}
