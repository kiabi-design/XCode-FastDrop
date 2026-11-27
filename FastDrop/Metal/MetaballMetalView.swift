import SwiftUI
import MetalKit

// ──────────────────────────────────────────────────────────────
// METAL VIEW REPRESENTABLE
// ──────────────────────────────────────────────────────────────

struct MetaballMetalView: UIViewRepresentable {
    @ObservedObject var renderer: MetaballRenderer
    let onDragChanged: ((CGPoint) -> Void)?
    let onDragEnded: ((CGPoint, Bool) -> Void)?

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
        metalView.contentScaleFactor = UIScreen.main.scale
        metalView.contentMode = .scaleToFill
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        metalView.addGestureRecognizer(pan)
        metalView.isUserInteractionEnabled = true

        return metalView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Update screen geometry for scatter calculations
        let scale = uiView.contentScaleFactor
        renderer.updateScreenGeometry(
            width: Float(uiView.bounds.width * scale),
            height: Float(uiView.bounds.height * scale),
            sendButtonCenter: SIMD2<Float>(Float(uiView.bounds.midX * scale), Float((uiView.bounds.height - 120) * scale)),
            screenCenter: SIMD2<Float>(Float(uiView.bounds.midX * scale), Float(uiView.bounds.midY * scale))
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTKView, context: Context) -> CGSize? {
        // Allow the MTKView to fill the GeometryReader
        return nil
    }
}

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer,
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: MetaballRenderer
        let onDragChanged: ((CGPoint) -> Void)?
        let onDragEnded: ((CGPoint, Bool) -> Void)?

        // Drag state (matching concept exactly)
        private var dragStartLocation: CGPoint = .zero
        private var dragOffset: CGPoint = .zero
        private var dragVelocity: CGPoint = .zero
        private var isDragging: Bool = false
        private var dragSpringActive: Bool = false
        private var halfHapticTriggered: Bool = false
        private var lastPanTime: CFTimeInterval = 0
        private var lastPanLocation: CGPoint = .zero

        // Spring constants from concept: k=170, c=16
        private let springK: Float = 170
        private let springC: Float = 16

        init(renderer: MetaballRenderer,
             onDragChanged: ((CGPoint) -> Void)?,
             onDragEnded: ((CGPoint, Bool) -> Void)?) {
            self.renderer = renderer
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            print("📐 MetaballMetalView: drawableSizeWillChange \(size)")
        }

        func draw(in view: MTKView) {
            // Skip if drawable size is zero (view not laid out yet)
            guard view.drawableSize.width > 0, view.drawableSize.height > 0,
                  let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else {
                print("⚠️ MetaballMetalView: draw skipped - drawableSize=\(view.drawableSize) drawable=\(view.currentDrawable != nil) descriptor=\(view.currentRenderPassDescriptor != nil)")
                return
            }

            // Update spring physics for drag return
            updateDragSpring(dt: 1.0/60.0)

            // Compute passes
            renderer.encodeComputePasses(commandBuffer: commandBuffer)

            // Render passes
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.03, green: 0.07, blue: 0.05, alpha: 1)
            descriptor.colorAttachments[0].storeAction = .store

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            renderer.encodeRenderPasses(renderEncoder: renderEncoder)

            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()

            if Int(CACurrentMediaTime() * 10) % 60 == 0 {
                print("🎨 MetaballMetalView: frame rendered size=\(view.drawableSize)")
            }
        }

        private func updateDragSpring(dt: Float) {
            guard dragSpringActive else { return }

            // Spring physics: v += (-k*x - c*v) * dt; x += v * dt
            let dx = Float(dragOffset.x)
            let dy = Float(dragOffset.y)
            let dvx = Float(dragVelocity.x)
            let dvy = Float(dragVelocity.y)

            let newVX = dvx + (-springK * dx - springC * dvx) * dt
            let newVY = dvy + (-springK * dy - springC * dvy) * dt
            let newX = dx + newVX * dt
            let newY = dy + newVY * dt

            dragVelocity.x = CGFloat(newVX)
            dragVelocity.y = CGFloat(newVY)
            dragOffset.x = CGFloat(newX)
            dragOffset.y = CGFloat(newY)

            // Check if settled
            if abs(dragOffset.x) < 0.3 && abs(dragOffset.y) < 0.3 &&
               abs(dragVelocity.x) + abs(dragVelocity.y) < 2 {
                dragOffset = .zero
                dragVelocity = .zero
                dragSpringActive = false
            }

            // Update renderer with current drag offset
            let dist = sqrtf(newX * newX + newY * newY)
            renderer.updateDragProgress(Float(dist / 150),
                                           dragOffset: SIMD2<Float>(newX, newY))
        }


        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let currentTime = CACurrentMediaTime()

            switch gesture.state {
            case .began:
                dragStartLocation = location
                dragOffset = .zero
                dragVelocity = .zero
                isDragging = true
                dragSpringActive = false
                halfHapticTriggered = false
                lastPanTime = currentTime
                lastPanLocation = location

                // Initial haptic
                HapticManager.impact(.light)

            case .changed:
                // Calculate velocity for flick detection
                let timeDelta = currentTime - lastPanTime
                if timeDelta > 0 {
                    dragVelocity.x = (location.x - lastPanLocation.x) / CGFloat(timeDelta)
                    dragVelocity.y = (location.y - lastPanLocation.y) / CGFloat(timeDelta)
                }
                lastPanTime = currentTime
                lastPanLocation = location

                guard let start = dragStartLocation as CGPoint? else { return }
                let translation = CGPoint(x: location.x - start.x, y: location.y - start.y)

                // Apply drag with resistance when can't send
                let canSend = renderer.drops.count > 0 // simplified check
                let resistance: CGFloat = canSend ? 1.0 : 0.12

                var newOffset = CGPoint(x: translation.x * resistance, y: translation.y * resistance)

                // Clamp when dragging towards center (like concept)
                if canSend {
                    let sbcx = CGFloat(renderer.sendButtonCenter.x)
                    let sbcy = CGFloat(renderer.sendButtonCenter.y)
                    let scx = CGFloat(renderer.screenCenter.x)
                    let scy = CGFloat(renderer.screenCenter.y)
                    let sw = CGFloat(renderer.screenWidth)
                    let sh = CGFloat(renderer.screenHeight)
                    let viewWidth = gesture.view!.bounds.width
                    let viewHeight = gesture.view!.bounds.height

                    let buttonCenter = CGPoint(x: sbcx / sw * viewWidth,
                                               y: sbcy / sh * viewHeight)
                    let screenCenter = CGPoint(x: scx / sw * viewWidth,
                                               y: scy / sh * viewHeight)

                    let maxX = screenCenter.x - buttonCenter.x
                    let maxY = screenCenter.y - buttonCenter.y

                    newOffset.x = clamp(newOffset.x + (buttonCenter.x - start.x),
                                       -buttonCenter.x + 40,
                                       viewWidth - buttonCenter.x - 40) - (buttonCenter.x - start.x)
                    newOffset.y = clamp(newOffset.y + (buttonCenter.y - start.y),
                                       -buttonCenter.y + 40,
                                       buttonCenter.y + 24 - start.y) - (buttonCenter.y - start.y)
                }

                dragOffset = newOffset

                // Progress calculation (distance to center / total distance)
                let sbcx = CGFloat(renderer.sendButtonCenter.x)
                let sbcy = CGFloat(renderer.sendButtonCenter.y)
                let scx = CGFloat(renderer.screenCenter.x)
                let scy = CGFloat(renderer.screenCenter.y)
                let totalDist = hypot(sbcx - scx, sbcy - scy)
                let currentDist = hypot(sbcx + dragOffset.x - scx,
                                       sbcy + dragOffset.y - scy)
                let progress = Float(max(0, min(1, 1 - currentDist / totalDist)))

                // Half haptic at 50% (concept: half=true at p>.5)
                if progress > 0.5 && !halfHapticTriggered {
                    halfHapticTriggered = true
                    HapticManager.impact(.rigid)
                } else if progress < 0.4 {
                    halfHapticTriggered = false
                }

                // Auto-trigger at 96% (concept: p>=.96)
                if progress >= 0.96 && canSend {
                    triggerSend(gesture: gesture)
                    return
                }

                onDragChanged?(translation)

            case .ended, .cancelled:
                guard isDragging else { return }
                isDragging = false

                let velocity = gesture.velocity(in: gesture.view)
                let dragDistance = hypot(dragOffset.x, dragOffset.y)

                // Trigger conditions from concept:
                // - distance > 120pt (prog >= 0.78)
                // - or velocity > 500
                let shouldTrigger = dragDistance > 120 || hypot(velocity.x, velocity.y) > 500

                if shouldTrigger && canSend() {
                    triggerSend(gesture: gesture)
                } else {
                    // Spring back
                    dragSpringActive = true
                    dragVelocity = CGPoint(x: velocity.x * 0.001, y: velocity.y * 0.001)
                    halfHapticTriggered = false

                    if !canSend() {
                        HapticManager.impact(.medium)
                    }
                }

                onDragEnded?(location, shouldTrigger && canSend())
                dragOffset = .zero
                dragSpringActive = false

            default:
                break
            }
        }

        private func canSend() -> Bool {
            renderer.drops.count > 0
        }

        private func triggerSend(gesture: UIPanGestureRecognizer) {
            dragSpringActive = false
            dragVelocity = .zero
            dragOffset = .zero
            isDragging = false

            // Spring to center
            let sbcx = CGFloat(renderer.sendButtonCenter.x)
            let sbcy = CGFloat(renderer.sendButtonCenter.y)
            let scx = CGFloat(renderer.screenCenter.x)
            let scy = CGFloat(renderer.screenCenter.y)
            let sw = CGFloat(renderer.screenWidth)
            let sh = CGFloat(renderer.screenHeight)
            let viewWidth = gesture.view?.bounds.width ?? 390
            let viewHeight = gesture.view?.bounds.height ?? 844

            let targetX = scx / sw * viewWidth - sbcx / sw * viewWidth
            let targetY = scy / sh * viewHeight - sbcy / sh * viewHeight

            dragOffset = CGPoint(x: targetX, y: targetY)
            dragSpringActive = true
            dragVelocity = .zero

            HapticManager.impact(.heavy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { HapticManager.impact(.rigid) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { HapticManager.impact(.heavy) }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) { [weak self] in
                self?.renderer.startSending(to: "target")
            }
        }

        private func clamp(_ value: CGFloat, _ min: CGFloat, _ max: CGFloat) -> CGFloat {
            Swift.max(min, Swift.min(max, value))
        }
    }
}

// ──────────────────────────────────────────────────────────────
// BACKGROUND VIEW WITH DRAG-TO-SEND BUTTON
// ──────────────────────────────────────────────────────────────

struct MetaballBackgroundView: View {
    @StateObject var renderer: MetaballRenderer
    @Binding var dragProgress: Float
    @Binding var isDragging: Bool
    let onSendTrigger: () -> Void
    let canSend: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                MetaballMetalView(
                    renderer: renderer,
                    onDragChanged: { translation in
                        let distToCenter = hypot(translation.x, translation.y)
                        let maxDist: CGFloat = 150
                        let progress = min(Float(distToCenter / maxDist), 1.0)

                        DispatchQueue.main.async {
                            dragProgress = canSend ? progress : progress * 0.12
                            isDragging = true
                        }
                    },
                    onDragEnded: { location, shouldTrigger in
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                dragProgress = 0
                                isDragging = false
                            }
                            if shouldTrigger && canSend {
                                onSendTrigger()
                            }
                        }
                    }
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    SendButtonView(
                        progress: dragProgress,
                        isDragging: isDragging,
                        canSend: canSend,
                        onTap: { }
                    )
                    .padding(.bottom, 50)
                }
            }
        }
    }
}

// ──────────────────────────────────────────────────────────────
// SEND BUTTON WITH PROGRESS RING (1:1 from concept)
// ──────────────────────────────────────────────────────────────

struct SendButtonView: View {
    let progress: Float
    let isDragging: Bool
    let canSend: Bool
    let onTap: () -> Void

    @State private var pulse = false
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 1

    var body: some View {
        ZStack {
            // Pulse ring when idle (concept: .rip animation)
            if !isDragging && canSend {
                Circle()
                    .stroke(Color.fdAccent, lineWidth: 2)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                            pulseScale = 1.75
                            pulseOpacity = 0
                        }
                    }
            }

            // Progress ring (concept: .pr .c with stroke-dashoffset)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(
                        colors: [Color.fdAccent.opacity(0.65), Color.fdAccent],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * Double(max(progress, 0.002)))
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round) // concept: stroke-width:5
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.1), value: progress)
                .shadow(color: Color.fdAccent.opacity(0.45), radius: 10)

            // Center button (concept: #sbi)
            Button(action: {
                if canSend { onTap() }
            }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: canSend
                                        ? [Color.fdAccent, Color(red: 0.08, green: 0.63, blue: 0.18)]
                                        : [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .scaleEffect(isDragging ? 1.1 : (progress > 0 ? 1.05 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
            .opacity(canSend || isDragging ? 1 : 0.45)
            .animation(.easeOut(duration: 0.35), value: canSend)
        }
        .frame(width: 84, height: 84)
    }
}