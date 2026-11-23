import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var settings = SettingsService.shared
    @State private var saveDirText: String = ""
    @State private var nameText: String = ""
    @State private var showFolderPicker = false
    
    var body: some View {
        let isWhite = settings.isWhiteTheme
        let palette = GlassPalette(isWhite: isWhite)
        
        LiquidBackground(isWhite: isWhite) {
            NavigationStack {
                List {
                    // Theme
                    Section {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Белый фон")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(palette.fg)
                                    Text(isWhite ? "Включён белый фон" : "Включён OLED-чёрный фон")
                                        .font(.system(size: 13))
                                        .foregroundStyle(palette.subtle)
                                }
                                Spacer()
                                Toggle("", isOn: $settings.isWhiteTheme)
                                    .labelsHidden()
                                    .tint(palette.accent)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } header: {
                        GlassLabel("ОБЩЕЕ", isWhite: isWhite)
                            .padding(.leading, 16)
                    }
                    
                    // Device Name
                    Section {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)) {
                            VStack(alignment: .leading, spacing: 12) {
                                GlassLabel("НАЗВАНИЕ УСТРОЙСТВА", isWhite: isWhite)
                                GlassTextField(text: $nameText, isWhite: isWhite, placeholder: "iPhone", onSubmit: {
                                    settings.deviceName = nameText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : nameText.trimmingCharacters(in: .whitespaces)
                                })
                                Text("Так вас видят другие устройства")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.subtle)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    
                    // Save Directory
                    Section {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)) {
                            VStack(alignment: .leading, spacing: 12) {
                                GlassLabel("ПАПКА СОХРАНЕНИЯ", isWhite: isWhite)
                                
                                HStack {
                                    GlassTextField(text: $saveDirText, isWhite: isWhite, placeholder: "По умолчанию: Documents/FastDrop", onSubmit: {
                                        settings.customSaveDirectory = saveDirText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : saveDirText.trimmingCharacters(in: .whitespaces)
                                    })
                                    
                                    Button(action: { showFolderPicker = true }) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundStyle(palette.subtle)
                                            .frame(width: 44, height: 44)
                                    }
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        GlassChip(label: "Выбрать папку", icon: Image(systemName: "folder"), isWhite: isWhite) {
                                            showFolderPicker = true
                                        }
                                        GlassChip(label: "По умолчанию", isWhite: isWhite) {
                                            saveDirText = ""
                                            settings.customSaveDirectory = nil
                                        }
                                    }
                                }
                                
                                Text("Текущая: \(settings.saveDirectory().path)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.subtle)
                                    .lineLimit(1)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    
                    // History
                    Section {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    GlassLabel("ИСТОРИЯ (\(settings.history.count))", isWhite: isWhite)
                                    Spacer()
                                    if !settings.history.isEmpty {
                                        GlassButton(label: "Очистить", icon: Image(systemName: "trash"), isWhite: isWhite, danger: true) {
                                            settings.clearHistory()
                                        }
                                    }
                                }
                                
                                if settings.history.isEmpty {
                                    Text("История пока пуста")
                                        .font(.system(size: 14))
                                        .foregroundStyle(palette.subtle)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(settings.history.prefix(20)) { item in
                                            HistoryRow(item: item, isWhite: isWhite, palette: palette)
                                        }
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    
                    // About
                    Section {
                        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FastDrop v\(NetworkConstants.appVersion)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.fg)
                                Text("Высокоскоростная передача файлов по локальной сети")
                                    .font(.system(size: 13))
                                    .foregroundStyle(palette.subtle)
                                Text("TCP порт: \(NetworkConstants.transferPort) · UDP порт: \(NetworkConstants.discoveryPort)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.subtle)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationTitle("Настройки")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        GlassIconButton(icon: Image(systemName: "xmark"), isWhite: isWhite) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            nameText = settings.deviceName ?? ""
            saveDirText = settings.customSaveDirectory ?? ""
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                saveDirText = url.path
                settings.customSaveDirectory = url.path
            }
        }
    }
}

private struct HistoryRow: View {
    let item: TransferHistoryItem
    let isWhite: Bool
    let palette: GlassPalette
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.direction.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(item.direction.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.fg)
                    .lineLimit(1)
                Text("\(item.direction.rawValue) · \(item.formattedSize) · \(item.formattedDate)")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.subtle)
            }
        }
        .padding(.vertical, 4)
    }
}
