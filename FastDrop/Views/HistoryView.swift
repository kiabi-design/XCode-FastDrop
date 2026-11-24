import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsService
    @State private var selectedTab: TransferDirection = .sent

    var body: some View {
        let isWhite = settings.isWhiteTheme
        let palette = GlassPalette(isWhite: isWhite)

        let sentItems = settings.history.filter { $0.direction == .sent }
        let receivedItems = settings.history.filter { $0.direction == .received }
        let visibleItems = selectedTab == .sent ? sentItems : receivedItems

        LiquidBackground(isWhite: isWhite) {
            NavigationStack {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        TabButton(
                            title: "Отправлено (\(sentItems.count))",
                            icon: "arrow.up.circle.fill",
                            isSelected: selectedTab == .sent,
                            isWhite: isWhite,
                            palette: palette
                        ) { selectedTab = .sent }

                        TabButton(
                            title: "Принято (\(receivedItems.count))",
                            icon: "arrow.down.circle.fill",
                            isSelected: selectedTab == .received,
                            isWhite: isWhite,
                            palette: palette
                        ) { selectedTab = .received }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    if visibleItems.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: selectedTab == .sent ? "tray" : "tray.and.arrow.down")
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(palette.subtle)
                            Text(selectedTab == .sent ? "Ничего не отправлено" : "Ничего не принято")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(palette.subtle)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(visibleItems) { item in
                                HistoryRow(item: item, isWhite: isWhite, palette: palette, tappable: true)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            settings.removeHistoryItem(id: item.id)
                                        } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .navigationTitle("История")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        GlassIconButton(icon: Image(systemName: "xmark"), isWhite: isWhite, size: 36) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !visibleItems.isEmpty {
                            Button(role: .destructive) {
                                settings.clearHistory(direction: selectedTab)
                            } label: {
                                Text("Очистить")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.danger)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let isWhite: Bool
    let palette: GlassPalette
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            GlassCard(
                isWhite: isWhite,
                radius: 999,
                blur: 0,
                tint: isSelected ? palette.accent : nil,
                padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
            ) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(isSelected ? palette.accent : palette.fg)
            }
        }
        .buttonStyle(GlassPressStyle())
    }
}

struct HistoryRow: View {
    let item: TransferHistoryItem
    let isWhite: Bool
    let palette: GlassPalette
    var tappable: Bool = false

    var body: some View {
        let row = GlassCard(
            isWhite: isWhite,
            radius: 20,
            blur: 8,
            padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        ) {
            HStack(spacing: 12) {
                Image(systemName: item.direction.icon)
                    .font(.system(size: 22, weight: .medium))
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

                Spacer()

                if tappable && item.direction == .received {
                    Image(systemName: "folder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.subtle)
                }
            }
        }

        if tappable && item.direction == .received {
            Button {
                if FileManager.default.fileExists(atPath: item.savedPath) {
                    FileOpener.revealFolder(containing: item.savedPath)
                }
            } label: {
                row
            }
            .buttonStyle(GlassPressStyle(scale: 0.98))
        } else {
            row
        }
    }
}
