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

            let offset = sentBytes
            let length = min(
                NetworkConstants.chunkSize,
                Int(item.sizeBytes - sentBytes)
            )

            guard length > 0 else {
                self.onSendProgress?(
                    item.sizeBytes,
                    item.sizeBytes
                )

                SettingsService.shared.addHistoryItem(
                    TransferHistoryItem(
                        fileName: item.fileName,
                        sizeBytes: item.sizeBytes,
                        direction: .sent,
                        savedPath: url.path
                    )
                )

                connection.cancel()
                continuation.resume()
                return
            }

            do {
                let fileHandle = try FileHandle(
                    forReadingFrom: url
                )

                try fileHandle.seek(toOffset: UInt64(offset))

                let data = fileHandle.readData(ofLength: length)

                try fileHandle.close()

                connection.send(
                    content: data,
                    completion: .contentProcessed { [weak self] error in
                        Task { @MainActor in
                            guard let self = self else {
                                continuation.resume()
                                return
                            }

                            if let error = error {
                                logger.error("Chunk send error: \(error)")

                                self.onSendError?(
                                    "Ошибка отправки: \(error.localizedDescription)"
                                )

                                connection.cancel()
                                continuation.resume()
                                return
                            }

                            sentBytes += Int64(data.count)

                            let now = Date()
                            let elapsed = now.timeIntervalSince(lastProgressTime)

                            if elapsed >= 0.15 {
                                let chunkSpeed = Double(data.count) /
                                    (1024 * 1024) / elapsed

                                speeds.append(chunkSpeed)
                                lastProgressTime = now
                            }

                            self.onSendProgress?(
                                sentBytes,
                                item.sizeBytes
                            )

                            sendNextChunk()
                        }
                    }
                )

            } catch {
                logger.error("File read error: \(error)")

                self.onSendError?(
                    "Ошибка чтения файла: \(error.localizedDescription)"
                )

                connection.cancel()
                continuation.resume()
            }
        }

        sendNextChunk()
    }
