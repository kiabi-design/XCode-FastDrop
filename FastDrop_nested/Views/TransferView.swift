import SwiftUI

struct TransferView: View {
    @ObservedObject var viewModel: HomeViewModel
    
    var body: some View {
        let isWhite = viewModel.settings.isWhiteTheme
        let palette = GlassPalette(isWhite: isWhite)
        
        LiquidBackground(isWhite: isWhite) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    GlassChip(
                        label: viewModel.transferProgress.currentIndex > 0 && viewModel.transferProgress.totalCount > 0
                            ? "\(viewModel.transferProgress.currentIndex) / \(viewModel.transferProgress.totalCount)"
                            : (viewModel.transferProgress.totalBytes > 0 ? "Приём" : "Отправка"),
                        icon: Image(systemName: viewModel.transferProgress.totalBytes > 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill"),
                        isWhite: isWhite,
                        selected: true
                    ) {}
                    
                    Spacer()
                    
                    if viewModel.transferProgress.isTransferring {
                        GlassIconButton(icon: Image(systemName: "xmark.circle.fill"), isWhite: isWhite, danger: true) {
                            viewModel.cancelTransfer()
                        }
                    } else if viewModel.transferProgress.isCompleted && !viewModel.transferProgress.isError {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(palette.success)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                Spacer()
                
                // Main card
                GlassCard(isWhite: isWhite, radius: 36, blur: 15, padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)) {
                    VStack(spacing: 22) {
                        // Speed & ETA
                        HStack(alignment: .bottom, spacing: 6) {
                            Text(String(format: "%.1f", viewModel.transferProgress.speedMBps))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.fg)
                                .contentTransition(.numericText())
                            Text("МБ/с")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(palette.subtle)
                                .padding(.bottom, 4)
                            
                            Spacer()
                            
                            if viewModel.transferProgress.isTransferring {
                                GlassIconButton(icon: Image(systemName: "xmark"), isWhite: isWhite, danger: true, size: 44) {
                                    viewModel.cancelTransfer()
                                }
                            }
                        }
                        
                        Text(viewModel.transferProgress.etaText)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.subtle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Progress bar
                        GlassProgressBar(value: viewModel.transferProgress.progress, isWhite: isWhite, color: progressColor(palette), height: 12)
                        
                        HStack {
                            Text(viewModel.transferProgress.percentText)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.fg)
                            Spacer()
                            Text("\(viewModel.transferProgress.formattedTransferred) / \(viewModel.transferProgress.formattedTotal)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.subtle)
                        }
                        
                        // File name
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(viewModel.transferProgress.fileName.isEmpty ? "Файл" : viewModel.transferProgress.fileName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.fg)
                                    .lineLimit(2)
                                
                                if viewModel.transferProgress.isCompleted && !viewModel.transferProgress.isError && viewModel.transferProgress.savedFilePath != nil {
                                    Spacer()
                                    GlassIconButton(icon: Image(systemName: "folder.fill"), isWhite: isWhite, size: 42) {
                                        viewModel.openReceivedFolder()
                                    }
                                }
                            }
                            
                            Text(viewModel.transferProgress.statusText)
                                .font(.system(size: 14))
                                .foregroundStyle(statusColor(palette))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Stats
                        if viewModel.transferProgress.isCompleted && !viewModel.transferProgress.isError {
                            HStack(spacing: 10) {
                                StatCell(label: "Средняя", value: viewModel.transferProgress.avgSpeedMBps, palette: palette)
                                StatCell(label: "Макс", value: viewModel.transferProgress.maxSpeedMBps, palette: palette)
                                StatCell(label: "Мин", value: viewModel.transferProgress.minSpeedMBps, palette: palette)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Bottom actions
                bottomActions(isWhite: isWhite, palette: palette)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 0) }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
        }
    }
    
    @ViewBuilder
    private func bottomActions(isWhite: Bool, palette: GlassPalette) -> some View {
        let isDone = viewModel.transferProgress.isCompleted && !viewModel.transferProgress.isError
        let isSender = viewModel.transferProgress.totalBytes > 0 && viewModel.transferProgress.savedFilePath == nil
        
        if isSender && !viewModel.transferProgress.isTransferring && isDone {
            HStack(spacing: 12) {
                GlassButton(label: "Готово", isWhite: isWhite, active: true, expand: true) {
                    viewModel.doneTransfer()
                }
                GlassButton(label: "Отправить ещё", icon: Image(systemName: "plus"), isWhite: isWhite, expand: true) {
                    viewModel.sendMore()
                }
            }
        } else if !isSender && !viewModel.transferProgress.isTransferring && isDone {
            GlassButton(label: "Готово", isWhite: isWhite, active: true, expand: true) {
                viewModel.doneTransfer()
            }
        } else {
            GlassButton(label: "Отмена", icon: Image(systemName: "xmark"), isWhite: isWhite, danger: true, expand: true) {
                viewModel.cancelTransfer()
            }
        }
    }
    
    private func progressColor(_ palette: GlassPalette) -> Color {
        if viewModel.transferProgress.isError { return palette.danger }
        if viewModel.transferProgress.isCompleted { return palette.success }
        return palette.accent
    }
    
    private func statusColor(_ palette: GlassPalette) -> Color {
        if viewModel.transferProgress.isError { return palette.danger }
        if viewModel.transferProgress.isCompleted { return palette.success }
        return palette.subtle
    }
}

private struct StatCell: View {
    let label: String
    let value: Double
    let palette: GlassPalette
    
    var body: some View {
        GlassCard(isWhite: palette.isWhite, radius: 18, blur: 0, padding: EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)) {
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
        }
        .frame(maxWidth: .infinity)
    }
}
