import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsService
    @State private var selectedTab: TransferDirection = .sent

    var body: some View {
        let items = settings.history.filter { $0.direction == selectedTab }

        NavigationStack {
            List {
                Section {
                    Picker("Тип", selection: $selectedTab) {
                        Text("Отправлено").tag(TransferDirection.sent)
                        Text("Принято").tag(TransferDirection.received)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    ForEach(items) { item in
                        HistoryRow(item: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    settings.removeHistoryItem(id: item.id)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { FDBackground() }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        selectedTab == .sent ? "Ничего не отправлено" : "Ничего не принято",
                        systemImage: selectedTab == .sent ? "tray" : "tray.and.arrow.down"
                    )
                }
            }
            .navigationTitle("История")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !items.isEmpty {
                        Button("Очистить", role: .destructive) {
                            settings.clearHistory(direction: selectedTab)
                        }
                    }
                }
            }
        }
    }
}

struct HistoryRow: View {
    let item: TransferHistoryItem

    var body: some View {
        let row = HStack(spacing: 12) {
            Image(systemName: item.direction.icon)
                .font(.title2)
                .foregroundStyle(item.direction.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(item.formattedSize) · \(item.formattedDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.direction == .received {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            }
        }

        if item.direction == .received {
            Button {
                if FileManager.default.fileExists(atPath: item.savedPath) {
                    FileOpener.revealFolder(containing: item.savedPath)
                }
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }
}
