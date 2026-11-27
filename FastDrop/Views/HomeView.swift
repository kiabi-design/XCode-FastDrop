import SwiftUI
import UniformTypeIdentifiers

// Import the DocumentPicker
// (already in same module, no import needed)

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var settings: SettingsService

    @State private var metalRenderer: MetaballRenderer? = MetaballRenderer.makeRenderer()

    var body: some View {
        ZStack {
            // Metal background with drag-to-send
            if let renderer = metalRenderer {
                MetaballBackgroundView(
                    renderer: renderer,
                    dragProgress: $viewModel.dragProgress,
                    isDragging: $viewModel.isDragging,
                    onSendTrigger: { viewModel.startSending() },
                    canSend: viewModel.canSend
                )
                .ignoresSafeArea()
                .onAppear {
                    viewModel.setMetalRenderer(renderer)
                }
            } else {
                // Fallback if Metal unavailable
                FDBackground()
                    .ignoresSafeArea()
            }

            NavigationStack {
                ScrollView {
                    VStack(spacing: 26) {
                        myIPsSection
                        peersSection
                        targetSection
                        selectedFilesSection
                        // Drop zone replaced by Metal background
                        receiveToggle
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 160) // Space for send button
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color.clear)
                .navigationTitle("FastDrop")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel("История")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.pickFiles()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Добавить файлы")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Настройки")
                    }
                }
            }

            if viewModel.showStatusCard {
                VStack {
                    Text(viewModel.statusMessage)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .fdGlass(in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(5)
            }

            if viewModel.showTransferScreen {
                if let renderer = viewModel.metalRenderer {
                    TransferSceneView(
                        renderer: renderer,
                        viewModel: viewModel,
                        onCancel: { viewModel.cancelTransfer() },
                        onDone: { viewModel.doneTransfer() },
                        onSendMore: { viewModel.sendMore() }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                } else {
                    TransferView(viewModel: viewModel)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showTransferScreen)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.showStatusCard)
        .sheet(isPresented: $viewModel.showDocumentPicker) {
            DocumentPicker(
                allowedContentTypes: [.item, .folder, .fileURL, .data],
                allowsMultipleSelection: true,
                onPick: { urls in
                    viewModel.handleDocumentPick(urls)
                },
                onCancel: {
                    viewModel.handleDocumentPickerCancel()
                }
            )
            .ignoresSafeArea()
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

    // MARK: - Sections (defined as computed properties within body scope via closures)

    @ViewBuilder
    private var myIPsSection: some View {
        if !viewModel.myIPs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                FDSectionHeader("Мои IP-адреса")

                ScrollView(.horizontal, showsIndicators: false) {
                    FDGlassContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.myIPs, id: \.self) { ip in
                                Button {
                                    viewModel.copyIPToClipboard(ip)
                                } label: {
                                    Label(ip, systemImage: "wifi")
                                        .font(.subheadline.monospaced())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .fdGlass(in: Capsule(), interactive: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FDSectionHeader("Устройства поблизости") {
                if viewModel.isListening {
                    Label("Готов", systemImage: "circle.fill")
                        .labelStyle(StatusDotStyle(color: .fdAccent))
                } else if let error = viewModel.listenError {
                    Label(error, systemImage: "circle.fill")
                        .labelStyle(StatusDotStyle(color: .red))
                        .lineLimit(2)
                }
            }

            if viewModel.discoveredPeers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Устройств не найдено")
                        .font(.headline)
                    Text("Убедитесь, что устройства в одной Wi-Fi сети и FastDrop запущен. Можно ввести IP вручную.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        viewModel.refreshNetwork()
                    } label: {
                        Label("Обновить", systemImage: "arrow.clockwise")
                    }
                    .fdButtonStyle()
                    .buttonBorderShape(.capsule)
                }
                .frame(maxWidth: .infinity)
                .fdCard(radius: 28, padding: 22)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    FDGlassContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(viewModel.discoveredPeers) { peer in
                                PeerCard(peer: peer, isSelected: peer.ip == viewModel.targetIP) {
                                    HapticManager.selection()
                                    viewModel.targetIP = peer.ip
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FDSectionHeader("Получатель")

            HStack(spacing: 10) {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
                TextField("IP-адрес, например 192.168.0.10", text: $viewModel.targetIP)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .submitLabel(.done)
                if !viewModel.targetIP.isEmpty {
                    Button {
                        viewModel.targetIP = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .fdGlass(in: Capsule())

            if !viewModel.targetIP.isEmpty && !viewModel.isTargetValid {
                Text("Введите корректный IPv4-адрес")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
            }
        }
    }

    @ViewBuilder
    private var selectedFilesSection: some View {
        if !viewModel.selectedItems.isEmpty {
            let total = viewModel.selectedItems.reduce(Int64(0)) { $0 + $1.sizeBytes }

            VStack(alignment: .leading, spacing: 10) {
                FDSectionHeader("Выбрано: \(viewModel.selectedItems.count)") {
                    Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.selectedItems.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: fileIconName(for: item.fileName))
                                .font(.title3)
                                .foregroundStyle(Color.fdAccent)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.fileName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                withAnimation { viewModel.removeSelectedItem(item) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 10)

                        if index < viewModel.selectedItems.count - 1 {
                            Divider()
                        }
                    }
                }
                .fdCard(radius: 26, padding: 16)
            }
        }
    }

    @ViewBuilder
    private var receiveToggle: some View {
        HStack(spacing: 14) {
            Image(systemName: viewModel.receiveEnabled ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(viewModel.receiveEnabled ? Color.fdAccent : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Принимать файлы")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.receiveEnabled ? "Порт \(String(NetworkConstants.transferPort))" : "Приём отключён")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $viewModel.receiveEnabled)
                .labelsHidden()
        }
        .fdCard(radius: 26, padding: 16)
    }

    // MARK: - Drop handling

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

// MARK: - Peer card

private struct PeerCard: View {
    let peer: DiscoveredPeer
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: peer.icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.fdAccent)

                Text(peer.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(peer.ip)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 118)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .fdGlass(
                in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                tint: isSelected ? Color.fdAccent.opacity(0.4) : nil,
                interactive: true
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StatusDotStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 6))
                .foregroundStyle(color)
            configuration.title
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
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