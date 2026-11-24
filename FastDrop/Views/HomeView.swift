import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var settings: SettingsService

    var body: some View {
        let isWhite = settings.isWhiteTheme
        let palette = GlassPalette(isWhite: isWhite)

        LiquidBackground(isWhite: isWhite) {
            ZStack {
                mainContent(isWhite: isWhite, palette: palette)

                if viewModel.showStatusCard {
                    VStack {
                        Spacer()
                        GlassCard(
                            isWhite: isWhite,
                            radius: 20,
                            blur: 10,
                            padding: EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
                        ) {
                            Text(viewModel.statusMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.fg)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .zIndex(5)
                }

                if viewModel.showTransferScreen {
                    TransferView(viewModel: viewModel)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.showTransferScreen)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showStatusCard)
        }
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            viewModel.handleImport(result)
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $viewModel.showHistory) {
            HistoryView()
                .environmentObject(settings)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $viewModel.dropHover) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Layout

    private func mainContent(isWhite: Bool, palette: GlassPalette) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar(isWhite: isWhite, palette: palette)

                if !viewModel.myIPs.isEmpty {
                    myIPsSection(isWhite: isWhite, palette: palette)
                }

                peersSection(isWhite: isWhite, palette: palette)
                targetSection(isWhite: isWhite, palette: palette)

                if !viewModel.selectedItems.isEmpty {
                    selectedFilesSection(isWhite: isWhite, palette: palette)
                }

                dropZoneSection(isWhite: isWhite, palette: palette)

                if !viewModel.selectedItems.isEmpty {
                    sendButtonSection(isWhite: isWhite)
                }

                receiveToggleSection(isWhite: isWhite, palette: palette)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
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
                        Button {
                            viewModel.copyIPToClipboard(ip)
                        } label: {
                            GlassCard(
                                isWhite: isWhite,
                                radius: 16,
                                blur: 8,
                                padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
                            ) {
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
                        }
                        .buttonStyle(GlassPressStyle())
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 4)
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
                        Text("Порт \(String(NetworkConstants.transferPort))")
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
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if viewModel.discoveredPeers.isEmpty {
                GlassCard(
                    isWhite: isWhite,
                    radius: 20,
                    blur: 8,
                    padding: EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)
                ) {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(palette.subtle)
                        Text("Устройств не найдено")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.subtle)
                        Text("Убедитесь, что другие устройства в одной Wi-Fi сети и запустили FastDrop. Можно ввести IP вручную ниже.")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.subtle.opacity(0.8))
                            .multilineTextAlignment(.center)
                        GlassButton(
                            label: "Обновить",
                            icon: Image(systemName: "arrow.clockwise"),
                            isWhite: isWhite
                        ) {
                            viewModel.refreshNetwork()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.discoveredPeers) { peer in
                            PeerCard(
                                peer: peer,
                                isSelected: peer.ip == viewModel.targetIP,
                                isWhite: isWhite,
                                palette: palette
                            ) {
                                viewModel.targetIP = peer.ip
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func targetSection(isWhite: Bool, palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassLabel("ПОЛУЧАТЕЛЬ (IP)", isWhite: isWhite)
            GlassTextField(
                text: $viewModel.targetIP,
                isWhite: isWhite,
                placeholder: "192.168.0.10",
                keyboardType: .numbersAndPunctuation
            )
            if !viewModel.targetIP.isEmpty && !viewModel.isTargetValid {
                Text("Введите корректный IPv4-адрес")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.danger)
            }
        }
        .padding(.vertical, 4)
    }

    private func selectedFilesSection(isWhite: Bool, palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GlassLabel("ВЫБРАНО (\(viewModel.selectedItems.count))", isWhite: isWhite)
                Spacer()
                let totalSize = viewModel.selectedItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
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
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func dropZoneSection(isWhite: Bool, palette: GlassPalette) -> some View {
        Button {
            viewModel.pickFiles()
        } label: {
            GlassCard(
                isWhite: isWhite,
                radius: 28,
                blur: 12,
                padding: EdgeInsets(top: 36, leading: 24, bottom: 36, trailing: 24)
            ) {
                VStack(spacing: 16) {
                    Image(systemName: viewModel.dropHover ? "tray.and.arrow.down.fill" : "square.and.arrow.down.on.square")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(viewModel.dropHover ? palette.accent : palette.subtle)
                        .scaleEffect(viewModel.dropHover ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.dropHover)

                    VStack(spacing: 4) {
                        Text(viewModel.dropHover ? "Отпустите файлы сюда" : "Нажмите, чтобы выбрать файлы")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.fg)
                        Text("или перетащите их сюда")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.subtle)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(GlassPressStyle(scale: 0.985))
        .padding(.vertical, 8)
    }

    private func sendButtonSection(isWhite: Bool) -> some View {
        let label: String
        if viewModel.targetIP.isEmpty {
            label = "Выберите устройство"
        } else if !viewModel.isTargetValid {
            label = "Некорректный IP"
        } else {
            label = "Отправить на \(viewModel.targetIP)"
        }

        return GlassButton(
            label: label,
            icon: Image(systemName: "paperplane.fill"),
            isWhite: isWhite,
            active: viewModel.canSend,
            expand: true
        ) {
            viewModel.startSending()
        }
        .disabled(!viewModel.canSend)
        .padding(.vertical, 8)
    }

    private func receiveToggleSection(isWhite: Bool, palette: GlassPalette) -> some View {
        GlassCard(
            isWhite: isWhite,
            radius: 20,
            blur: 8,
            padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        ) {
            HStack {
                Image(systemName: viewModel.receiveEnabled ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(viewModel.receiveEnabled ? palette.success : palette.subtle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Принимать файлы")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.fg)
                    Text(viewModel.receiveEnabled ? "Готов к приёму на порту \(String(NetworkConstants.transferPort))" : "Приём отключён")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.subtle)
                }

                Spacer()

                Toggle("", isOn: $viewModel.receiveEnabled)
                    .labelsHidden()
                    .tint(palette.accent)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !accepted.isEmpty else { return false }

        let box = URLBox()
        let group = DispatchGroup()

        for provider in accepted {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    box.append(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    box.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = box.urls
            guard !urls.isEmpty else { return }
            Task { @MainActor in viewModel.addFiles(urls) }
        }
        return true
    }
}

/// Thread-safe collector for URLs delivered by NSItemProvider callbacks.
private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

// MARK: - Peer Card

private struct PeerCard: View {
    let peer: DiscoveredPeer
    let isSelected: Bool
    let isWhite: Bool
    let palette: GlassPalette
    let onTap: () -> Void

    var body: some View {
        Button {
            HapticManager.impact(.light)
            onTap()
        } label: {
            GlassCard(
                isWhite: isWhite,
                radius: 20,
                blur: 8,
                tint: isSelected ? palette.accent : nil,
                padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            ) {
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
                }
                .frame(width: 130)
            }
        }
        .buttonStyle(GlassPressStyle(scale: 0.95))
    }
}

// MARK: - Selected File Card

private struct SelectedFileCard: View {
    let item: OutgoingItem
    let isWhite: Bool
    let palette: GlassPalette
    let onRemove: () -> Void

    var body: some View {
        GlassCard(
            isWhite: isWhite,
            radius: 18,
            blur: 8,
            padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        ) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
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
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    HapticManager.impact(.light)
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(palette.subtle)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 190)
        }
    }

    private var iconName: String {
        switch item.url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo.fill"
        case "mp4", "mov", "mkv", "avi": return "video.fill"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
        default: return "doc.fill"
        }
    }
}
