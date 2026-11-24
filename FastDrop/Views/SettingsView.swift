import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsService
    @State private var nameText: String = ""
    @State private var showFolderPicker = false

    var body: some View {
        let isWhite = settings.isWhiteTheme
        let palette = GlassPalette(isWhite: isWhite)

        LiquidBackground(isWhite: isWhite) {
            NavigationStack {
                List {
                    row {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: cardPadding) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Светлая тема")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(palette.fg)
                                    Text(isWhite ? "Светлый фон" : "OLED-чёрный фон")
                                        .font(.system(size: 13))
                                        .foregroundStyle(palette.subtle)
                                }
                                Spacer()
                                Toggle("", isOn: $settings.isWhiteTheme)
                                    .labelsHidden()
                                    .tint(palette.accent)
                            }
                        }
                    }

                    row {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: cardPadding) {
                            VStack(alignment: .leading, spacing: 12) {
                                GlassLabel("НАЗВАНИЕ УСТРОЙСТВА", isWhite: isWhite)
                                GlassTextField(
                                    text: $nameText,
                                    isWhite: isWhite,
                                    placeholder: UIDevice.current.name,
                                    onSubmit: commitName
                                )
                                Text("Так вас видят другие устройства")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.subtle)
                            }
                        }
                    }

                    row {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: cardPadding) {
                            VStack(alignment: .leading, spacing: 12) {
                                GlassLabel("ПАПКА СОХРАНЕНИЯ", isWhite: isWhite)

                                Text(settings.saveFolderDescription)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.fg)
                                    .lineLimit(2)

                                HStack(spacing: 8) {
                                    GlassChip(
                                        label: "Выбрать папку",
                                        icon: Image(systemName: "folder"),
                                        isWhite: isWhite
                                    ) {
                                        showFolderPicker = true
                                    }
                                    if settings.usesCustomSaveFolder {
                                        GlassChip(label: "По умолчанию", isWhite: isWhite) {
                                            settings.resetSaveFolder()
                                        }
                                    }
                                }

                                Text("По умолчанию файлы лежат в «Файлы → На iPhone → FastDrop».")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.subtle)
                            }
                        }
                    }

                    row {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: cardPadding) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    GlassLabel("ИСТОРИЯ (\(settings.history.count))", isWhite: isWhite)
                                    Spacer()
                                    if !settings.history.isEmpty {
                                        Button(role: .destructive) {
                                            settings.clearHistory()
                                        } label: {
                                            Text("Очистить")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(palette.danger)
                                        }
                                    }
                                }

                                if settings.history.isEmpty {
                                    Text("История пока пуста")
                                        .font(.system(size: 14))
                                        .foregroundStyle(palette.subtle)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(settings.history.prefix(5)) { item in
                                            HistoryRow(item: item, isWhite: isWhite, palette: palette)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    row {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: cardPadding) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FastDrop v\(NetworkConstants.appVersion)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.fg)
                                Text("Быстрая передача файлов по локальной сети")
                                    .font(.system(size: 13))
                                    .foregroundStyle(palette.subtle)
                                Text("TCP \(String(NetworkConstants.transferPort)) · Bonjour \(NetworkConstants.serviceType)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.subtle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationTitle("Настройки")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        GlassIconButton(icon: Image(systemName: "xmark"), isWhite: isWhite, size: 36) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { nameText = settings.deviceName ?? "" }
        .onDisappear { commitName() }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                settings.setSaveFolder(url)
            }
        }
    }

    private var cardPadding: EdgeInsets {
        EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func commitName() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue: String? = trimmed.isEmpty ? nil : trimmed
        if newValue != settings.deviceName {
            settings.deviceName = newValue
        }
    }
}
