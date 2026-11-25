import SwiftUI

struct TransferView: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        let p = viewModel.transferProgress

        ZStack {
            FDBackground()

            VStack(spacing: 0) {
                header(p)

                Spacer(minLength: 12)

                ring(p)

                VStack(spacing: 6) {
                    Text(p.fileName.isEmpty ? "Файл" : p.fileName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(p.statusText)
                        .font(.subheadline)
                        .foregroundStyle(statusColor(p))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 22)
                .padding(.horizontal, 12)

                Spacer(minLength: 12)

                stats(p)
                    .padding(.bottom, 16)

                actions(p)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Parts

    private func header(_ p: TransferProgress) -> some View {
        HStack {
            Label(
                p.totalCount > 1 ? "\(p.currentIndex) из \(p.totalCount)" : (p.isSending ? "Отправка" : "Приём"),
                systemImage: p.isSending ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .fdGlass(in: Capsule())

            Spacer()

            if viewModel.isTransferring {
                FDIconButton(systemName: "xmark", tint: .red) {
                    viewModel.cancelTransfer()
                }
            }
        }
        .padding(.top, 12)
    }

    private func ring(_ p: TransferProgress) -> some View {
        ZStack {
            FDProgressRing(value: p.progress, color: ringColor(p), lineWidth: 18)

            VStack(spacing: 2) {
                if p.isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(.red)
                } else if p.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.fdAccent)
                        .symbolEffect(.bounce, value: p.isCompleted)
                } else {
                    Text(String(format: "%.1f", p.speedMBps))
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("МБ/с")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(p.percentText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .frame(width: 252, height: 252)
    }

    private func stats(_ p: TransferProgress) -> some View {
        HStack(spacing: 0) {
            if p.isCompleted && !p.isError {
                StatCell(title: "Средняя", value: speedText(p.avgSpeedMBps), unit: "МБ/с")
                StatDivider()
                StatCell(title: "Макс.", value: speedText(p.maxSpeedMBps), unit: "МБ/с")
                StatDivider()
                StatCell(title: "Мин.", value: speedText(p.minSpeedMBps), unit: "МБ/с")
            } else {
                StatCell(title: "Осталось", value: p.etaText, unit: nil)
                StatDivider()
                StatCell(title: "Передано", value: p.formattedTransferred, unit: nil)
                StatDivider()
                StatCell(title: "Всего", value: p.formattedTotal, unit: nil)
            }
        }
        .fdCard(radius: 28, padding: 14)
    }

    @ViewBuilder
    private func actions(_ p: TransferProgress) -> some View {
        if viewModel.isTransferring {
            Button(role: .destructive) {
                viewModel.cancelTransfer()
            } label: {
                Label("Отменить", systemImage: "xmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .fdButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.red)
        } else if p.isError {
            Button {
                viewModel.doneTransfer()
            } label: {
                Text("Закрыть")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .fdButtonStyle(prominent: true)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        } else {
            HStack(spacing: 12) {
                if p.isSending {
                    Button {
                        viewModel.sendMore()
                    } label: {
                        Label("Ещё", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .fdButtonStyle()
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                } else if p.savedFilePath != nil {
                    Button {
                        viewModel.openReceivedFolder()
                    } label: {
                        Label("Папка", systemImage: "folder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .fdButtonStyle()
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }

                Button {
                    viewModel.doneTransfer()
                } label: {
                    Text("Готово")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .fdButtonStyle(prominent: true)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Helpers

    private func ringColor(_ p: TransferProgress) -> Color {
        if p.isError { return .red }
        return .fdAccent
    }

    private func statusColor(_ p: TransferProgress) -> Color {
        if p.isError { return .red }
        if p.isCompleted { return .fdAccent }
        return .secondary
    }

    private func speedText(_ value: Double) -> String {
        value > 0 ? String(format: "%.1f", value) : "—"
    }
}

private struct StatCell: View {
    let title: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let unit = unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatDivider: View {
    var body: some View {
        Divider().frame(height: 34)
    }
}
