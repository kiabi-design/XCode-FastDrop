import SwiftUI
import MetalKit

// ──────────────────────────────────────────────────────────────
// TRANSFER SCENE - Full screen "void" during sending (1:1 from concept #xf/#xc)
// ──────────────────────────────────────────────────────────────

struct TransferSceneView: View {
    @ObservedObject var renderer: MetaballRenderer
    @ObservedObject var viewModel: HomeViewModel
    let onCancel: () -> Void
    let onDone: () -> Void
    let onSendMore: () -> Void

    @State private var animateIn = false
    @State private var showStats = false
    @State private var currentFileIndex = 0
    @State private var speeds: [Double] = []
    @State private var minSpeed: Double = 99
    @State private var maxSpeed: Double = 0
    @State private var sumSpeed: Double = 0
    @State private var speedCount: Int = 0

    var body: some View {
        ZStack {
            // Metal background with void, disk, ripple, checkmark
            TransferMetalView(renderer: renderer)
                .ignoresSafeArea()

            // UI Overlay (concept #xc)
            VStack(spacing: 0) {
                // Header with chip and close
                HStack {
                    Label(
                        renderer.drops.count > 1 ? "\(currentFileIndex + 1) из \(renderer.drops.count)" :
                            (renderer.isSending ? "Отправка" : "Приём"),
                        systemImage: renderer.isSending ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .fdGlass(in: Capsule())

                    Spacer()

                    if renderer.isSending && !renderer.sendCompleted {
                        Button {
                            renderer.cancelSending()
                            onCancel()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 20)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : -20)

                Spacer(minLength: 12)

                // File name and status
                VStack(spacing: 6) {
                    Text(currentFileName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 22)
                .padding(.horizontal, 12)
                .opacity(animateIn ? 1 : 0)
                .scaleEffect(animateIn ? 1 : 0.9)

                Spacer(minLength: 12)

                // Stats (concept .stats)
                if showStats {
                    statsView
                        .transition(.opacity.combined(with: .scale))
                }

                Spacer(minLength: 16)

                // Actions
                actionsView
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                animateIn = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showStats = true
                }
            }
            startSpeedSampling()
        }
        .onDisappear {
            stopSpeedSampling()
        }
    }

    private var currentFileName: String {
        if renderer.sendSceneDrops.indices.contains(currentFileIndex) {
            return renderer.sendSceneDrops[currentFileIndex].fileName
        }
        return viewModel.transferProgress.fileName
    }

    private var statusText: String {
        if renderer.sendCompleted {
            return "Все файлы поглощены — отправка завершена"
        } else if renderer.isSending {
            return "Отправка на \(viewModel.targetIP.trimmingCharacters(in: .whitespaces))…"
        } else if viewModel.transferProgress.isCompleted {
            return "Файл принят"
        } else if viewModel.transferProgress.isError {
            return viewModel.transferProgress.statusText
        }
        return "Подготовка…"
    }

    private var statusColor: Color {
        if renderer.sendCompleted { return .fdAccent }
        if viewModel.transferProgress.isError { return .red }
        return .secondary
    }

    private var statsView: some View {
        let p = viewModel.transferProgress
        let isCompleted = renderer.sendCompleted || (p.isCompleted && !p.isError)

        return HStack(spacing: 0) {
            if isCompleted {
                StatCell(title: "Средняя", value: speedText(sumSpeed / Double(max(speedCount, 1))), unit: "МБ/с")
                StatDivider()
                StatCell(title: "Макс.", value: speedText(maxSpeed), unit: "МБ/с")
                StatDivider()
                StatCell(title: "Мин.", value: speedText(minSpeed), unit: "МБ/с")
            } else {
                StatCell(title: "Осталось", value: p.etaText, unit: nil)
                StatDivider()
                StatCell(title: "Передано", value: p.formattedTransferred, unit: nil)
                StatDivider()
                StatCell(title: "Всего", value: p.formattedTotal, unit: nil)
            }
        }
        .fdCard(radius: 28, padding: 14)
    }

    private var actionsView: some View {
        Group {
            if renderer.isSending && !renderer.sendCompleted {
                Button(role: .destructive) {
                    renderer.cancelSending()
                    onCancel()
                } label: {
                    Label("Отменить", systemImage: "xmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .fdButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.red)
            } else if renderer.sendCompleted {
                // Concept: checkmark shown, actions = + Ещё / Готово
                HStack(spacing: 12) {
                    Button {
                        onSendMore()
                    } label: {
                        Label("Ещё", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .fdButtonStyle()
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)

                    Button {
                        onDone()
                    } label: {
                        Text("Готово")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .fdButtonStyle(prominent: true)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            } else if viewModel.transferProgress.isError {
                Button {
                    onDone()
                } label: {
                    Text("Закрыть")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .fdButtonStyle(prominent: true)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            } else {
                HStack(spacing: 12) {
                    if viewModel.transferProgress.isSending {
                        Button {
                            onSendMore()
                        } label: {
                            Label("Ещё", systemImage: "plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .fdButtonStyle()
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                    } else if viewModel.transferProgress.savedFilePath != nil {
                        Button {
                            viewModel.openReceivedFolder()
                        } label: {
                            Label("Папка", systemImage: "folder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .fdButtonStyle()
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                    }

                    Button {
                        onDone()
                    } label: {
                        Text("Готово")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .fdButtonStyle(prominent: true)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            }
        }
    }

    private func speedText(_ value: Double) -> String {
        value > 0 ? String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",") : "—"
    }

    private func startSpeedSampling() {
        // Sample speed like concept: 18+14*sin(t*1.3)+6*sin(t*3.7)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            guard renderer.isSending && !renderer.sendCompleted else {
                timer.invalidate()
                return
            }
            // Simulate network speed variation
            let t = Date().timeIntervalSince1970
            let sp = 18 + 14 * sin(t * 1.3) + 6 * sin(t * 3.7)
            speeds.append(sp)
            minSpeed = min(minSpeed, sp)
            maxSpeed = max(maxSpeed, sp)
            sumSpeed += sp
            speedCount += 1
        }
    }

    private func stopSpeedSampling() {
        // Timer auto-invalidates
    }
}

// ──────────────────────────────────────────────────────────────
// TRANSFER METAL VIEW - Full screen renderer for send scene
// ──────────────────────────────────────────────────────────────

struct TransferMetalView: UIViewRepresentable {
    @ObservedObject var renderer: MetaballRenderer

    func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView(frame: .zero, device: renderer.device)
        metalView.delegate = context.coordinator
        metalView.preferredFramesPerSecond = 60
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.framebufferOnly = false
        metalView.backgroundColor = .clear
        return metalView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: MetaballRenderer

        init(renderer: MetaballRenderer) {
            self.renderer = renderer
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            // Skip if drawable size is zero (view not laid out yet)
            guard view.drawableSize.width > 0, view.drawableSize.height > 0,
                  let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else { return }

            // Compute passes
            renderer.encodeComputePasses(commandBuffer: commandBuffer)

            // Render passes
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            descriptor.colorAttachments[0].storeAction = .store

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            renderer.encodeRenderPasses(renderEncoder: renderEncoder)

            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

// ──────────────────────────────────────────────────────────────
// STAT CELLS
// ──────────────────────────────────────────────────────────────

private struct StatCell: View {
    let title: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let unit = unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatDivider: View {
    var body: some View {
        Divider().frame(height: 34)
    }
}