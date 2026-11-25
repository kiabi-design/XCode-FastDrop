import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsService
    @State private var nameText: String = ""
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Оформление") {
                    Picker("Тема", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField(UIDevice.current.name, text: $nameText)
                        .submitLabel(.done)
                        .onSubmit(commitName)
                } header: {
                    Text("Название устройства")
                } footer: {
                    Text("Так вас видят другие устройства.")
                }

                Section {
                    LabeledContent("Сейчас") {
                        Text(settings.saveFolderDescription)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    Button("Выбрать папку…") { showFolderPicker = true }
                    if settings.usesCustomSaveFolder {
                        Button("Вернуть по умолчанию") { settings.resetSaveFolder() }
                    }
                } header: {
                    Text("Папка сохранения")
                } footer: {
                    Text("По умолчанию: «Файлы → На iPhone → FastDrop».")
                }

                Section("История") {
                    LabeledContent("Записей", value: "\(settings.history.count)")
                    if !settings.history.isEmpty {
                        Button("Очистить историю", role: .destructive) {
                            settings.clearHistory()
                        }
                    }
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: NetworkConstants.appVersion)
                    LabeledContent("Порт", value: String(NetworkConstants.transferPort))
                    LabeledContent("Обнаружение", value: "Bonjour")
                }
            }
            .scrollContentBackground(.hidden)
            .background { FDBackground() }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
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

    private func commitName() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue: String? = trimmed.isEmpty ? nil : trimmed
        if newValue != settings.deviceName {
            settings.deviceName = newValue
        }
    }
}
