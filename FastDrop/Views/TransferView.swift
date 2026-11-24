import SwiftUI

struct TransferView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject private var settings: SettingsService

    var body: some View {
        let isWhite = settings.isWhiteTheme
        let palette = GlassPalette(isWhite: isWhite)
        let p = viewModel.transferProgress

        LiquidBackground(isWhite: isWhite) {
            VStack(spacing: 0) {
                header(p: p, isWhite: isWhite, palette: palette)

                Spacer()

                GlassCard(
                    isWhite: isWhite,
                    radius: 36,
                    blur: 15,
                    padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
                ) {
                    VStack(spacing: 20) {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", p.speedMBps))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.fg)
                                .contentTransition(.numericText())
                            Text("МБ/с")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(palette.subtle)
                            Spacer()
                        }

                        Text(p.etaText)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.subtle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        GlassProgressBar(
                            value: p.progress,
                            isWhite: isWhite,
                            color: progressColor(p, palette),
                            height: 12
                        )

                        HStack {
                            Text(p.percentText)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.fg)
                            Spacer()
                            Text("\(p.formattedTransferred) / \(p.formattedTotal)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.subtle)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(p.fileName.isEmpty ? "Файл" : p.fileName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.fg)
                                    .lineLimit(2)

                                if p.isCompleted && !p.isError && p.savedFilePath != nil {
                                    Spacer()
                                    GlassIconButton(
                                        icon: Image(systemName: "folder.fill"),
                                        isWhite: isWhite,
                                        size: 42
                                    ) {
                                        viewModel.openReceivedFolder()
                                    }
                                }
                            }

                            Text(p.statusText)
                                .font(.system(size: 14))
                                .foregroundStyle(statusColor(p, palette))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if p.isCompleted && !p.isError {
                            HStack(spacing: 10) {
                                StatCell(label: "Средняя", value: p.avgSpeedMBps, palette: palette)
                                StatCell(label: "Макс", value: p.maxSpeedMBps, palette: palette)
                                StatCell(label: "Мин", value: p.minSpeedMBps, palette: palette)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                bottomActions(p: p, isWhite: isWhite)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
    }

    private func header(p: TransferProgress, isWhite: Bool, palette: GlassPalette) -> some View {
        HStack {
            GlassChip(
                label: p.totalCount > 1 ? "\(p.currentIndex) / \(p.totalCount)" : (p.isSending ? "Отправка" : "Приём"),
                icon: Image(systemName: p.isSending ? "arrow.up.circle.fill" : "arrow.down.circle.fill"),
                isWhite: isWhite,
                selected: true
            ) {}
            .allowsHitTesting(false)

            Spacer()

            if viewModel.isTransferring {
                GlassIconButton(icon: Image(systemName: "xmark"), isWhite: isWhite, danger: true) {
                    viewModel.cancelTransfer()
                }
            } else if p.isCompleted && !p.isError {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(palette.success)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func bottomActions(p: TransferProgress, isWhite: Bool) -> some View {
        if viewModel.isTransferring {
            GlassButton(label: "Отмена", icon: Image(systemName: "xmark"), isWhite: isWhite, danger: true, expand: true) {
                viewModel.cancelTransfer()
            }
        } else if p.isError {
            GlassButton(label: "Закрыть", isWhite: isWhite, expand: true) {
                viewModel.doneTransfer()
            }
        } else if p.isSending {
            HStack(spacing: 12) {
                GlassButton(label: "Готово", isWhite: isWhite, active: true, expand: true) {
                    viewModel.doneTransfer()
                }
                GlassButton(label: "Ещё", icon: Image(systemName: "plus"), isWhite: isWhite, expand: true) {
                    viewModel.sendMore()
                }
            }
        } else {
            GlassButton(label: "Готово", isWhite: isWhite, active: true, expand: true) {
                viewModel.doneTransfer()
            }
        }
    }

    private func progressColor(_ p: TransferProgress, _ palette: GlassPalette) -> Color {
        if p.isError { return palette.danger }
        if p.isCompleted { return palette.success }
        return palette.accent
    }

    private func statusColor(_ p: TransferProgress, _ palette: GlassPalette) -> Color {
        if p.isError { return palette.danger }
        if p.isCompleted { return palette.success }
        return palette.subtle
    }
}

private struct StatCell: View {
    let label: String
    let value: Double
    let palette: GlassPalette

    var body: some View {
        GlassCard(
            isWhite: palette.isWhite,
            radius: 18,
            blur: 0,
            padding: EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        ) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.subtle)
                Text(value > 0 ? String(format: "%.1f", value) : "—")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.fg)
                Text("МБ/с")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.subtle)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
