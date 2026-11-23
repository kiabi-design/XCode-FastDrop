import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @StateObject var viewModel = HomeViewModel()
    @Environment(\.colorScheme) var systemColorScheme
    @State private var showPeerPicker = false
    
    var body: some View {
        let isWhite = viewModel.settings.isWhiteTheme
        let palette = GlassPalette(isWhite: isWhite)
        
        LiquidBackground(isWhite: isWhite) {
            ZStack {
                mainContent(isWhite: isWhite, palette: palette)
                
                // Status card
                if viewModel.showStatusCard {
                    VStack {
                        Spacer()
                        GlassCard(isWhite: isWhite, radius: 20, blur: 10, padding: EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)) {
                            Text(viewModel.statusMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.fg)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showStatusCard)
                }
                
                // Transfer screen overlay
                if viewModel.showTransferScreen {
                    TransferView(viewModel: viewModel)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.showTransferScreen)
        }
        .sheet(isPresented: $viewModel.showFilePicker) {
            DocumentPicker { urls in
                viewModel.handleDroppedFiles(urls)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $viewModel.showHistory) {
            HistoryView()
                .presentationDetents([.large])
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $viewModel.dropHover) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    @ViewBuilder
    private func mainContent(isWhite: Bool, palette: GlassPalette) -> some View {
        VStack(spacing: 0) {
            // Top bar
            topBar(isWhite: isWhite, palette: palette)
            
            // My IPs
            if !viewModel.myIPs.isEmpty {
                myIPsSection(isWhite: isWhite, palette: palette)
            }
            
            // Peers
            peersSection(isWhite: isWhite, palette: palette)
            
            Spacer(minLength: 20)
            
            // Selected files
            if !viewModel.selectedItems.isEmpty {
                selectedFilesSection(isWhite: isWhite, palette: palette)
            }
            
            // Drop zone / main action area
            dropZoneSection(isWhite: isWhite, palette: palette)
            
            // Send button
            if !viewModel.selectedItems.isEmpty {
                sendButtonSection(isWhite: isWhite, palette: palette)
            }
            
            // Receive toggle
            receiveToggleSection(isWhite: isWhite, palette: palette)
            
            Spacer(minLength: 30)
        }
        .padding(.horizontal, 16)
    }
    
    private func topBar(isWhite: Bool, palette: GlassPalette) -> some View {
        HStack {
            GlassIconButton(icon: Image(systemName: "clock.arrow.circlepath"), isWhite: isWhite) {
                viewModel.showHistory = true
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("FastDrop")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.fg)
                Text("v\(NetworkConstants.appVersion)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.subtle)
            }
            
            Spacer()
            
            GlassIconButton(icon: Image(systemName: "gearshape.fill"), isWhite: isWhite) {
                viewModel.showSettings = true
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    private func myIPsSection(isWhite: Bool, palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassLabel("МОИ IP-АДРЕСА", isWhite: isWhite)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.myIPs, id: \.self) { ip in
                        GlassCard(isWhite: isWhite, radius: 16, blur: 8, padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)) {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(palette.accent)
                                Text(ip)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.fg)
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(palette.subtle)
                            }
                        }
                        .onTapGesture {
                            viewModel.copyIPToClipboard(ip)
                        }
                        .contextMenu {
                            Button("Копировать") { viewModel.copyIPToClipboard(ip) }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func peersSection(isWhite: Bool, palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GlassLabel("УСТРОЙСТВА В СЕТИ", isWhite: isWhite)
                Spacer()
                if viewModel.isListening {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(palette.success)
                            .frame(width: 6, height: 6)
                            .opacity(0.8)
                        Text("Слушает порт \(NetworkConstants.transferPort)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.success)
                    }
                } else if let error = viewModel.listenError {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(palette.danger)
                            .frame(width: 6, height: 6)
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.danger)
                    }
                }
            }
            
            if viewModel.discoveredPeers.isEmpty {
                GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)) {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(palette.subtle)
                        Text("Устройств не найдено")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.subtle)
                        Text("Убедитесь, что другие устройства в одной Wi-Fi сети и запустили FastDrop")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.subtle.opacity(0.7))
                            .multilineTextAlignment(.center)
                        GlassButton(label: "Обновить", icon: Image(systemName: "arrow.clockwise"), isWhite: isWhite, expand: true) {
                            viewModel.refreshNetwork()
                        }
                        .frame(width: 160)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.discoveredPeers) { peer in
                            PeerCard(peer: peer, isWhite: isWhite, palette: palette) {
                                viewModel.targetIP = peer.ip
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func selectedFilesSection(isWhite: Bool, palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GlassLabel("ВЫБРАНО (\(viewModel.selectedItems.count))", isWhite: isWhite)
                Spacer()
                let totalSize = viewModel.selectedItems.reduce(0) { $0 + $1.sizeBytes }
                Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.subtle)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.selectedItems) { item in
                        SelectedFileCard(item: item, isWhite: isWhite, palette: palette) {
                            viewModel.removeSelectedItem(item)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func dropZoneSection(isWhite: Bool, palette: GlassPalette) -> some View {
        GlassCard(isWhite: isWhite, radius: 28, blur: 12, padding: EdgeInsets(top: 40, leading: 24, bottom: 40, trailing: 24)) {
            VStack(spacing: 16) {
                Image(systemName: viewModel.dropHover ? "tray.and.arrow.down.fill" : "square.and.arrow.down.on.square")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(viewModel.dropHover ? palette.accent : palette.subtle)
                    .scaleEffect(viewModel.dropHover ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.dropHover)
                
                VStack(spacing: 4) {
                    Text(viewModel.dropHover ? "Отпустите файлы сюда" : "Перетащите файлы сюда")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.fg)
                    Text("или нажмите, чтобы выбрать")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.subtle)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onTapGesture {
            viewModel.pickFiles()
        }
        .padding(.vertical, 8)
    }
    
    private func sendButtonSection(isWhite: Bool, palette: GlassPalette) -> some View {
        HStack(spacing: 12) {
            if !viewModel.targetIP.isEmpty {
                GlassButton(
                    label: "Отправить на \(viewModel.targetIP)",
                    icon: Image(systemName: "paperplane.fill"),
                    isWhite: isWhite,
                    active: true,
                    expand: true
                ) {
                    viewModel.startSending()
                }
            } else {
                GlassButton(
                    label: "Выберите устройство →",
                    icon: Image(systemName: "hand.point.right"),
                    isWhite: isWhite,
                    expand: true
                ) {
                    // Just visual hint
                }
                .disabled(true)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func receiveToggleSection(isWhite: Bool, palette: GlassPalette) -> some View {
        GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)) {
            HStack {
                Image(systemName: viewModel.receiveEnabled ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(viewModel.receiveEnabled ? palette.success : palette.subtle)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Принимать файлы")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.fg)
                    Text(viewModel.receiveEnabled ? "Готов к приёму на порту \(NetworkConstants.transferPort)" : "Приём отключён")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.subtle)
                }
                
                Spacer()
                
                Toggle("", isOn: $viewModel.receiveEnabled)
                    .labelsHidden()
                    .tint(palette.accent)
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if !urls.isEmpty {
                viewModel.handleDroppedFiles(urls)
            }
        }
        
        return true
    }
}

// MARK: - Peer Card
private struct PeerCard: View {
    let peer: DiscoveredPeer
    let isWhite: Bool
    let palette: GlassPalette
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.light)
            onTap()
        }) {
            GlassCard(isWhite: isWhite, radius: 20, blur: 8, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(spacing: 10) {
                    Image(systemName: peer.icon)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(palette.accent)
                    
                    Text(peer.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.fg)
                        .lineLimit(1)
                    
                    Text(peer.ip)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtle)
                    
                    Text(peer.os)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.subtle.opacity(0.7))
                }
                .frame(width: 140)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.11), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.11)) { isPressed = pressing }
        }, perform: {})
    }
}

// MARK: - Selected File Card
private struct SelectedFileCard: View {
    let item: OutgoingItem
    let isWhite: Bool
    let palette: GlassPalette
    let onRemove: () -> Void
    
    var body: some View {
        GlassCard(isWhite: isWhite, radius: 18, blur: 8, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            HStack(spacing: 10) {
                fileIcon(for: item)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(palette.accent)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.fg)
                        .lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtle)
                }
                
                Button(action: {
                    HapticManager.impact(.light)
                    onRemove()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(palette.subtle)
                }
            }
            .frame(width: 180)
        }
    }
    
    private func fileIcon(for item: OutgoingItem) -> Image {
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return Image(systemName: "photo.fill")
        case "mp4", "mov", "mkv", "avi": return Image(systemName: "video.fill")
        case "pdf": return Image(systemName: "doc.fill")
        case "zip", "rar", "7z", "tar", "gz": return Image(systemName: "archivebox.fill")
        case "apk", "ipa": return Image(systemName: "app.fill")
        default: return Image(systemName: "doc.fill")
        }
    }
}

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
