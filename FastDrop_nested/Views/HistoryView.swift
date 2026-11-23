import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var settings = SettingsService.shared
    @State private var selectedTab: TransferDirection = .sent
    
    var body: some View {
        let isWhite = settings.isWhiteTheme
        let palette = GlassPalette(isWhite: isWhite)
        
        let sentItems = settings.history.filter { $0.direction == .sent }
        let receivedItems = settings.history.filter { $0.direction == .received }
        
        LiquidBackground(isWhite: isWhite) {
            NavigationStack {
                VStack(spacing: 0) {
                    // Tab selector
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
                    
                    // List
                    if (selectedTab == .sent ? sentItems : receivedItems).isEmpty {
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
                            ForEach(selectedTab == .sent ? sentItems : receivedItems) { item in
                                HistoryRow(item: item, isWhite: isWhite, palette: palette)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            settings.history.removeAll { $0.id == item.id }
                                            settings.saveHistory()
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
                        GlassIconButton(icon: Image(systemName: "xmark"), isWhite: isWhite) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !settings.history.isEmpty {
                            GlassButton(label: "Очистить вкладку", icon: Image(systemName: "trash"), isWhite: isWhite, danger: true) {
                                settings.clearHistory(direction: selectedTab)
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
        Button(action: {
            HapticManager.impact(.light)
            action()
        }) {
            GlassCard(isWhite: isWhite, radius: 999, blur: 0, tint: isSelected ? palette.accent : nil, padding: EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(isSelected ? (isWhite ? .black : .white) : palette.fg)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryRow: View {
    let item: TransferHistoryItem
    let isWhite: Bool
    let palette: GlassPalette
    
    var body: some View {
        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)) {
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
                
                if item.direction == .received {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.subtle)
                }
            }
        }
        .onTapGesture {
            if item.direction == .received {
                let url = URL(fileURLWithPath: item.savedPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}
