import Foundation
import Metal
import MetalKit
import simd
import SwiftUI

// ──────────────────────────────────────────────────────────────
// FILE LOGGER (readable via Files.app / LiveContainer)
// ──────────────────────────────────────────────────────────────

final class FileLogger {
    static let shared = FileLogger()
    private let url: URL
    private let queue = DispatchQueue(label: "fastdrop.logger")

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logDir = docs.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        url = logDir.appendingPathComponent("fastdrop.log")
        write("=== FastDrop Log Started ===")
    }

    func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.url.path) {
                    if let handle = try? FileHandle(forWritingTo: self.url) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.url)
                }
            }
        }
        print(message) // Also to console for Xcode users
    }
}

// Convenience
func FLog(_ message: String) { FileLogger.shared.write(message) }

// ──────────────────────────────────────────────────────────────
// DATA MODELS (match Metal structs exactly)
// ──────────────────────────────────────────────────────────────

struct DropParticle: Equatable {
    var position: SIMD2<Float> = .zero
    var radius: Float = 0.12
    var phase: Float = 0
    var verticalVelocity: Float = 0
    var isAlive: Bool = true
    var targetPosition: SIMD2<Float>? = nil
    var state: State = .idle
    var progress: Float = 0
    var sendStartTime: Double = 0
    var duration: Float = 1.5
    var fileName: String = "file"
    var fileSize: Int64 = 0

    // Scatter positions (for send scene)
    var scatterPos: SIMD2<Float>? = nil
    var inSendScene: Bool = false

    // Ghost animation (on remove)
    var isGhost: Bool = false
    var ghostStartTime: Double = 0

    // Pull animation params
    var pullStartPos: SIMD2<Float>? = nil
    var pullStartRadius: Float = 0
    var pullStartAngle: Float = 0

    enum State: Equatable {
        case idle
        case wait
        case ring
        case pull
        case gone
    }

    var metalDrop: MetalDrop {
        MetalDrop(
            pos: position,
            radius: radius,
            phase: phase,
            vy: verticalVelocity,
            alive: isAlive ? 1 : 0,
            _pad: (0, 0)
        )
    }
}

struct MetalDrop {
    var pos: SIMD2<Float>
    var radius: Float
    var phase: Float
    var vy: Float
    var alive: UInt32
    var _pad: (Float, Float)

    init(pos: SIMD2<Float>, radius: Float, phase: Float, vy: Float, alive: UInt32, _pad: (Float, Float)) {
        self.pos = pos
        self.radius = radius
        self.phase = phase
        self.vy = vy
        self.alive = alive
        self._pad = _pad
    }
}

// ──────────────────────────────────────────────────────────────
// UNIFORMS (matches Metal shader struct exactly)
// ──────────────────────────────────────────────────────────────

struct MetaballUniforms {
    var resolution: SIMD2<Float> = .zero
    var gridResolution: SIMD2<Float> = SIMD2<Float>(128, 128)
    var time: Float = 0
    var threshold: Float = 0.55
    var dropCount: UInt32 = 0
    var blurRadius: Float = 2.5
    var colorMatrix: (Float, Float, Float, Float,
                      Float, Float, Float, Float,
                      Float, Float, Float, Float,
                      Float, Float, Float, Float) = (1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1)
    var highlightIntensity: Float = 1.0
    var shadowIntensity: Float = 1.0
    var bodyOpacity: Float = 0.96
    var rimPower: Float = 3.0
    var rimIntensity: Float = 0.45
    // Void params
    var voidProgress: Float = 0
    var voidScale: Float = 1.0
    // Disk params
    var diskRotation: Float = 0
    var diskOpacity: Float = 0
    // Ripple params
    var rippleProgress: Float = 0
    var rippleCenter: SIMD2<Float> = .zero
    var rippleMaxRadius: Float = 0
    // Checkmark params
    var checkProgress: Float = 0
    var checkCenter: SIMD2<Float> = .zero
    var checkSize: Float = 0

    init() {}
}

// ──────────────────────────────────────────────────────────────
// METAL RENDERER
// ──────────────────────────────────────────────────────────────

final class MetaballRenderer: ObservableObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary

    var fieldSolvePipeline: MTLComputePipelineState!
    var blurHPipeline: MTLComputePipelineState!
    var blurVPipeline: MTLComputePipelineState!
    var normalsPipeline: MTLComputePipelineState!
    var metaballRenderPipeline: MTLRenderPipelineState!
    var voidRenderPipeline: MTLRenderPipelineState!
    var progressRingPipeline: MTLRenderPipelineState!
    var diskRenderPipeline: MTLRenderPipelineState!
    var rippleRenderPipeline: MTLRenderPipelineState!
    var checkmarkRenderPipeline: MTLRenderPipelineState!

    var dropBuffer: MTLBuffer!
    var fieldBufferA: MTLBuffer!
    var fieldBufferB: MTLBuffer!
    var normalsBuffer: MTLBuffer!
    var uniformsBuffer: MTLBuffer!

    var fieldTextureA: MTLTexture!
    var fieldTextureB: MTLTexture!
    var normalsTexture: MTLTexture!

    var quadVertexBuffer: MTLBuffer!

    @Published var drops: [DropParticle] = []
    @Published var isSending: Bool = false
    @Published var sendProgress: Float = 0
    @Published var sendPhase: DropParticle.State = .idle
    @Published var voidProgress: Float = 0

    // Send scene state
    @Published var sendSceneActive: Bool = false
    @Published var sendSceneDrops: [DropParticle] = []
    @Published var sendCompleted: Bool = false
    private var sendSceneStartTime: Double = 0
    private var sendTargetIP: String = ""
    private var sendCheckmarkProgress: Float = 0
    private var nextDropRingTime: Double = 0
    private var currentRingingIndex: Int = -1
    private var scatterPositions: [SIMD2<Float>] = []

    // Ripple animation
    private var activeRipple: Bool = false
    private var rippleStartTime: Double = 0
    private var rippleCenter: SIMD2<Float> = .zero

    private var lastFrameTime: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    let maxDrops = 32
    let fieldWidth = 128
    let fieldHeight = 128
    let baseDropRadius: Float = 0.12

    // Screen geometry (updated from view)
    var screenWidth: Float = 390
    var screenHeight: Float = 844
    var sendButtonCenter: SIMD2<Float> = .zero
    var screenCenter: SIMD2<Float> = .zero

    // Easing constants from concept
    let springK: Float = 170
    let springC: Float = 16

    init?(metalView: MTKView) {
        guard let device = metalView.device,
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            print("❌ Failed to create Metal device/queue/library")
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.library = library

        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.preferredFramesPerSecond = 60
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false

        commonInit()
    }

    private init(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary) {
        self.device = device
        self.commandQueue = commandQueue
        self.library = library
        commonInit()
    }

    static func makeRenderer() -> MetaballRenderer? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            print("❌ Failed to create Metal device/queue/library")
            return nil
        }
        return MetaballRenderer(device: device, commandQueue: commandQueue, library: library)
    }

    private func commonInit() {
        FLog("🔧 MetaballRenderer: commonInit started")
        setupPipelines()
        FLog("🔧 MetaballRenderer: pipelines created")
        setupBuffers()
        FLog("🔧 MetaballRenderer: buffers created")
        setupTextures()
        FLog("🔧 MetaballRenderer: textures created")
        setupGeometry()
        FLog("🔧 MetaballRenderer: geometry created")
        startAnimationLoop()
        FLog("🔧 MetaballRenderer: animation loop started")

        // Start with 3 drops like concept
        for _ in 0..<3 { addDrop() }
        FLog("🔧 MetaballRenderer: 3 drops added, count=\(drops.count)")

        // Force initial uniform update so first frame has data
        updateUniforms(time: 0)
        FLog("🔧 MetaballRenderer: initial uniforms updated")
    }

    deinit {
        stopAnimationLoop()
    }

    // ──────────────────────────────────────────────────────────────
    // PIPELINE SETUP
    // ──────────────────────────────────────────────────────────────

    private func setupPipelines() {
        fieldSolvePipeline = makeComputePipeline("metaball_field_solve")
        blurHPipeline = makeComputePipeline("gaussian_blur_h")
        blurVPipeline = makeComputePipeline("gaussian_blur_v")
        normalsPipeline = makeComputePipeline("compute_normals")

        metaballRenderPipeline = makeRenderPipeline(
            vertex: "metaball_vertex",
            fragment: "metaball_fragment",
            colorFormat: .bgra8Unorm,
            depthFormat: .depth32Float
        )

        voidRenderPipeline = makeRenderPipeline(
            vertex: "metaball_vertex",
            fragment: "void_fragment",
            colorFormat: .bgra8Unorm,
            depthFormat: .depth32Float
        )

        diskRenderPipeline = makeRenderPipeline(
            vertex: "metaball_vertex",
            fragment: "disk_fragment",
            colorFormat: .bgra8Unorm,
            depthFormat: .depth32Float
        )

        progressRingPipeline = makeRenderPipeline(
            vertex: "metaball_vertex",
            fragment: "progress_ring_fragment",
            colorFormat: .bgra8Unorm,
            depthFormat: .depth32Float
        )

        rippleRenderPipeline = makeRenderPipeline(
            vertex: "metaball_vertex",
            fragment: "ripple_fragment",
            colorFormat: .bgra8Unorm,
            depthFormat: .depth32Float
        )

        checkmarkRenderPipeline = makeRenderPipeline(
            vertex: "metaball_vertex",
            fragment: "checkmark_fragment",
            colorFormat: .bgra8Unorm,
            depthFormat: .depth32Float
        )
    }

    private func makeComputePipeline(_ name: String) -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: name),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            fatalError("❌ Failed to create compute pipeline: \(name)")
        }
        return pipeline
    }

    private func makeRenderPipeline(vertex: String, fragment: String,
                                     colorFormat: MTLPixelFormat,
                                     depthFormat: MTLPixelFormat) -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: vertex)
        desc.fragmentFunction = library.makeFunction(name: fragment)
        desc.colorAttachments[0].pixelFormat = colorFormat
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        desc.depthAttachmentPixelFormat = depthFormat

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else {
            fatalError("❌ Failed to create render pipeline: \(fragment)")
        }
        return pipeline
    }

    // ──────────────────────────────────────────────────────────────
    // BUFFERS & TEXTURES
    // ──────────────────────────────────────────────────────────────

    private func setupBuffers() {
        dropBuffer = device.makeBuffer(length: maxDrops * MemoryLayout<MetalDrop>.stride,
                                        options: .storageModeShared)

        let fieldSize = fieldWidth * fieldHeight * MemoryLayout<Float>.stride
        fieldBufferA = device.makeBuffer(length: fieldSize, options: .storageModeShared)
        fieldBufferB = device.makeBuffer(length: fieldSize, options: .storageModeShared)

        let normalsSize = fieldWidth * fieldHeight * MemoryLayout<SIMD2<Float>>.stride
        normalsBuffer = device.makeBuffer(length: normalsSize, options: .storageModeShared)

        uniformsBuffer = device.makeBuffer(length: MemoryLayout<MetaballUniforms>.stride,
                                           options: .storageModeShared)
    }

    private func setupTextures() {
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: fieldWidth,
            height: fieldHeight,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead, .shaderWrite]
        texDesc.storageMode = .shared
        fieldTextureA = device.makeTexture(descriptor: texDesc)
        fieldTextureB = device.makeTexture(descriptor: texDesc)

        // Normals buffer is used directly in fragment shader (no texture needed)
        // normalsTexture is kept for compute shader output if needed
        let normalTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: fieldWidth,
            height: fieldHeight,
            mipmapped: false
        )
        normalTexDesc.usage = [.shaderRead, .shaderWrite]
        normalTexDesc.storageMode = .shared
        normalsTexture = device.makeTexture(descriptor: normalTexDesc)
    }

    private func setupGeometry() {
        struct QuadVertex { var position: SIMD2<Float>; var uv: SIMD2<Float> }
        let vertices: [QuadVertex] = [
            QuadVertex(position: SIMD2<Float>(-1, -1), uv: SIMD2<Float>(0, 1)),
            QuadVertex(position: SIMD2<Float>( 1, -1), uv: SIMD2<Float>(1, 1)),
            QuadVertex(position: SIMD2<Float>(-1,  1), uv: SIMD2<Float>(0, 0)),
            QuadVertex(position: SIMD2<Float>( 1,  1), uv: SIMD2<Float>(1, 0)),
        ]
        quadVertexBuffer = device.makeBuffer(bytes: vertices,
                                              length: vertices.count * MemoryLayout<QuadVertex>.stride,
                                              options: .storageModeShared)
    }

    // ──────────────────────────────────────────────────────────────
    // ANIMATION LOOP
    // ──────────────────────────────────────────────────────────────

    private func startAnimationLoop() {
        displayLink = CADisplayLink(target: self, selector: #selector(frameCallback(_:)))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopAnimationLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func frameCallback(_ link: CADisplayLink) {
        let currentTime = link.timestamp
        let dt = lastFrameTime > 0 ? min(Float(currentTime - lastFrameTime), 1.0/30.0) : 1.0/60.0
        lastFrameTime = currentTime

        updatePhysics(dt: dt, currentTime: currentTime)
        updateUniforms(time: Float(currentTime))

        if Int(currentTime * 10) % 60 == 0 {
            FLog("🎬 MetaballRenderer: frameCallback dt=\(dt) drops=\(drops.count) sendScene=\(sendSceneActive)")
        }
    }

    // ──────────────────────────────────────────────────────────────
    // EASING FUNCTIONS (1:1 from concept)
    // ──────────────────────────────────────────────────────────────

    // Smoothstep: x*x*(3-2*x)
    private func ss(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = clamp((x - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    }

    // Ease out back (eob from concept)
    private func eob(_ x: Float) -> Float {
        let c: Float = 1.70158
        return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2)
    }

    // Ease out elastic (eoe from concept)
    private func eoe(_ x: Float) -> Float {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return pow(2, -10 * x) * sin((x * 10 - 0.75) * 2.0944) + 1
    }

    // ──────────────────────────────────────────────────────────────
    // PHYSICS & LOGIC
    // ──────────────────────────────────────────────────────────────

    private func updatePhysics(dt: Float, currentTime: CFTimeInterval) {
        let now = currentTime

        // Update drag spring physics (from concept)
        updateDragSpring(dt: dt)

        if sendSceneActive {
            updateSendScene(dt: dt, now: now)
        } else {
            updateIdlePhysics(dt: dt, now: now)
        }

        // Update ripple
        if activeRipple {
            let elapsed = Float(now - rippleStartTime)
            if elapsed > 0.95 {
                activeRipple = false
            }
        }

        // Update checkmark
        if sendCompleted && sendCheckmarkProgress < 1 {
            sendCheckmarkProgress += dt / 0.6
            sendCheckmarkProgress = min(sendCheckmarkProgress, 1)
        }
    }

    private func updateDragSpring(dt: Float) {
        // Spring physics for drag return (k=170, c=16 from concept)
        // This is handled in the view, but we track the spring state
    }

    private func updateIdlePhysics(dt: Float, now: Double) {
        for i in drops.indices {
            var drop = drops[i]
            guard drop.isAlive else { continue }

            drop.phase += dt * 2.3

            if drop.state == .idle || drop.state == .wait {
                // Idle floating from concept: sin(phase*0.7)*8, cos(phase*0.55)*8
                let floatY = sin(drop.phase * 0.7) * 0.02
                let floatX = cos(drop.phase * 0.55) * 0.015
                drop.position.y += floatY * dt * 10
                drop.position.x += floatX * dt * 10

                drop.position.x = clamp(drop.position.x, 0.08, 0.92)
                drop.position.y = clamp(drop.position.y, 0.12, 0.88)
            }

            // Ghost fade out
            if drop.isGhost {
                let elapsed = Float(now - drop.ghostStartTime)
                if elapsed > 0.4 {
                    drop.isAlive = false
                }
            }

            drops[i] = drop
        }

        // Remove dead drops
        drops.removeAll { !$0.isAlive }
    }

    private func updateSendScene(dt: Float, now: Double) {
        let tt = Float(now - sendSceneStartTime)
        var allGone = true

        for i in sendSceneDrops.indices {
            var drop = sendSceneDrops[i]
            guard drop.isAlive else { continue }
            allGone = false

            drop.phase += dt * 2.3

            switch drop.state {
            case .wait:
                // Start ring when it's this drop's turn and no other is ringing
                if currentRingingIndex == -1 && i == nextRingIndex() {
                    drop.state = .ring
                    drop.sendStartTime = now
                    drop.progress = 0
                    currentRingingIndex = i
                    nextDropRingTime = now + 0.35 + Double(drop.duration)
                }

            case .ring:
                let elapsed = Float(now - drop.sendStartTime)
                let ringDelay: Float = 0.35
                if elapsed > ringDelay {
                    drop.progress = clamp((elapsed - ringDelay) / drop.duration, 0, 1)
                    if drop.progress >= 1 {
                        drop.state = .pull
                        drop.progress = 0
                        drop.pullStartPos = drop.position
                        drop.pullStartRadius = drop.radius
                        let dx = drop.position.x - 0.5
                        let dy = drop.position.y - 0.5
                        drop.pullStartAngle = atan2(dy, dx)
                    }
                }

            case .pull:
                let pullDuration: Float = 0.95
                drop.progress += dt / pullDuration
                if drop.progress >= 1 {
                    drop.state = .gone
                    drop.isAlive = false
                    // Trigger ripple at center
                    triggerRipple(at: SIMD2<Float>(0.5, 0.5))
                    HapticManager.impact(.rigid)
                } else {
                    let u = pow(drop.progress, 2.2)
                    let rho = lerp(0.35, 0, u)
                    let theta = lerp(drop.pullStartAngle ?? 0, (drop.pullStartAngle ?? 0) + 5.2, u)
                    drop.position = SIMD2<Float>(0.5 + cos(theta) * rho, 0.5 + sin(theta) * rho)
                    drop.radius = drop.pullStartRadius * (1 - 0.92 * pow(drop.progress, 2.6))
                }

            case .gone:
                drop.isAlive = false

            default:
                break
            }

            sendSceneDrops[i] = drop
        }

        // Check for next drop to ring
        if currentRingingIndex != -1 && now >= nextDropRingTime {
            currentRingingIndex = -1
        }

        // Update void progress
        voidProgress = clamp(tt * 2, 0, 1)

        // Update disk rotation
        // disk rotates continuously

        // Check completion
        if allGone && !sendCompleted {
            finishSendScene()
        }
    }

    private func nextRingIndex() -> Int {
        for (i, drop) in sendSceneDrops.enumerated() {
            if drop.state == .wait {
                return i
            }
        }
        return -1
    }

    private func finishSendScene() {
        sendCompleted = true
        sendCheckmarkProgress = 0
        voidProgress = 1.0
        HapticManager.notification(.success)
        HapticManager.impact(.heavy)

        // Trigger final ripple
        triggerRipple(at: SIMD2<Float>(0.5, 0.5))

        // Auto-reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.resetSendScene()
        }
    }

    private func resetSendScene() {
        sendSceneActive = false
        sendCompleted = false
        sendCheckmarkProgress = 0
        voidProgress = 0
        sendProgress = 0
        sendPhase = .idle
        currentRingingIndex = -1
        sendSceneDrops.removeAll()
        scatterPositions.removeAll()

        // Return remaining drops to idle
        for i in drops.indices {
            drops[i].state = .idle
            drops[i].inSendScene = false
            drops[i].scatterPos = nil
        }
    }

    // ──────────────────────────────────────────────────────────────
    // SCATTER (1:1 from concept)
    // ──────────────────────────────────────────────────────────────

    private func scatterDrops(_ dropsToScatter: [DropParticle]) -> [SIMD2<Float>] {
        var positions: [SIMD2<Float>] = []
        let cx = screenCenter.x / screenWidth
        let cy = screenCenter.y / screenHeight

        for drop in dropsToScatter {
            var best: SIMD2<Float>? = nil
            var bestDist: Float = -1

            for _ in 0..<70 {
                let x = Float.random(in: 48...(screenWidth - 96)) / screenWidth
                let y = Float.random(in: 112...(screenHeight - 112 - 270)) / screenHeight

                // Skip if too close to center
                let distToCenter = hypot(x - cx, y - cy)
                if distToCenter < 140 / screenWidth { continue }

                let minDist = positions.map { hypot($0.x - x, $0.y - y) }.min() ?? 999
                if minDist > bestDist {
                    bestDist = minDist
                    best = SIMD2<Float>(x, y)
                }
            }

            let finalPos = best ?? SIMD2<Float>(Float.random(in: 0.15...0.85), Float.random(in: 0.2...0.8))
            positions.append(finalPos)
        }

        return positions
    }

    // ──────────────────────────────────────────────────────────────
    // PUBLIC API
    // ──────────────────────────────────────────────────────────────

    func updateScreenGeometry(width: Float, height: Float, sendButtonCenter: SIMD2<Float>, screenCenter: SIMD2<Float>) {
        self.screenWidth = width
        self.screenHeight = height
        self.sendButtonCenter = sendButtonCenter
        self.screenCenter = screenCenter
    }

    func addDrop(at position: SIMD2<Float>? = nil, fileName: String = "file", fileSize: Int64 = 0) {
        guard drops.count < maxDrops else { return }

        let pos = position ?? SIMD2<Float>(
            Float.random(in: 0.15...0.85),
            Float.random(in: 0.2...0.8)
        )

        var bestPos = pos
        var bestDist: Float = 0
        for _ in 0..<28 {
            let candidate = SIMD2<Float>(
                Float.random(in: 0.15...0.85),
                Float.random(in: 0.2...0.8)
            )
            let minDist = drops.map { distance(candidate, $0.position) }.min() ?? 1
            if minDist > bestDist {
                bestDist = minDist
                bestPos = candidate
            }
        }

        // Radius based on file size (like concept: 26+16*clamp((log10(size)-3)/6, 0, 1))
        let sizeMB = Float(fileSize) / 1_048_576
        let logSize = log10(max(sizeMB * 1_000_000, 1))
        let radiusMultiplier = 26 + 16 * clamp((logSize - 3) / 6, 0, 1)
        let radius = (baseDropRadius * radiusMultiplier / 26) * Float.random(in: 0.9...1.1)

        var drop = DropParticle(
            position: bestPos,
            radius: radius,
            phase: Float.random(in: 0...6.28),
            verticalVelocity: 0,
            isAlive: true,
            state: .idle,
            duration: Float.random(in: 1.2...2.6),
            fileName: fileName,
            fileSize: fileSize
        )

        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            drops.append(drop)
        }
        HapticManager.impact(.light)
    }

    func removeDrop(at index: Int) {
        guard index < drops.count else { return }
        var drop = drops[index]
        drop.isGhost = true
        drop.ghostStartTime = CACurrentMediaTime()
        drop.state = .gone
        drops[index] = drop
        HapticManager.impact(.medium)
    }

    func startSending(to targetIP: String) {
        guard !drops.isEmpty, !isSending, !sendSceneActive else { return }

        sendTargetIP = targetIP
        sendSceneActive = true
        sendSceneStartTime = CACurrentMediaTime()
        sendCompleted = false
        sendCheckmarkProgress = 0
        currentRingingIndex = -1
        nextDropRingTime = sendSceneStartTime + 1.1 // First ring after 1.1s

        // Copy drops to send scene
        sendSceneDrops = drops
        for i in sendSceneDrops.indices {
            sendSceneDrops[i].state = .wait
            sendSceneDrops[i].progress = 0
            sendSceneDrops[i].inSendScene = true
        }

        // Scatter positions
        scatterPositions = scatterDrops(sendSceneDrops)
        for i in sendSceneDrops.indices {
            sendSceneDrops[i].scatterPos = scatterPositions[i]
            sendSceneDrops[i].targetPosition = scatterPositions[i]
        }

        // Scale durations based on count (concept: >5 drops -> 0.7x)
        let sc = sendSceneDrops.count > 5 ? 0.7 : 1.0
        for i in sendSceneDrops.indices {
            sendSceneDrops[i].duration *= Float(sc)
        }

        // Update main drops to match
        for i in drops.indices {
            drops[i].state = .wait
            drops[i].inSendScene = true
            if i < scatterPositions.count {
                drops[i].scatterPos = scatterPositions[i]
            }
        }

        isSending = true
        sendProgress = 0
        voidProgress = 0
        sendPhase = .ring

        // Haptic pattern from concept: [20, 30, 20] at trigger
        HapticManager.impact(.heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { HapticManager.impact(.rigid) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { HapticManager.impact(.heavy) }
    }

    func cancelSending() {
        if sendSceneActive {
            resetSendScene()
        } else {
            isSending = false
            for i in drops.indices {
                drops[i].state = .idle
                drops[i].progress = 0
            }
            voidProgress = 0
        }
        HapticManager.notification(.error)
    }

    func triggerRipple(at center: SIMD2<Float>) {
        activeRipple = true
        rippleStartTime = CACurrentMediaTime()
        rippleCenter = center
    }

    func updateDragProgress(_ progress: Float, dragOffset: SIMD2<Float>) {
        sendProgress = progress
        // Drag spring physics handled in view
    }

    func dragEnded(shouldTrigger: Bool) {
        sendProgress = 0
        if shouldTrigger && !drops.isEmpty {
            startSending(to: sendTargetIP)
        }
    }

    // ──────────────────────────────────────────────────────────────
    // UNIFORMS UPDATE
    // ──────────────────────────────────────────────────────────────

    private func updateUniforms(time: Float) {
        var uniforms = MetaballUniforms()
        uniforms.resolution = SIMD2<Float>(Float(fieldWidth), Float(fieldHeight))
        uniforms.gridResolution = SIMD2<Float>(Float(fieldWidth), Float(fieldHeight))
        uniforms.time = time
        uniforms.threshold = 0.55

        // Combine drops for field solving
        var allDrops = drops
        if sendSceneActive {
            allDrops = sendSceneDrops
        }
        uniforms.dropCount = UInt32(allDrops.count)
        uniforms.blurRadius = 2.5 + voidProgress * 1.5
        uniforms.bodyOpacity = 0.96
        uniforms.highlightIntensity = 1.0
        uniforms.shadowIntensity = 1.0
        uniforms.rimPower = 3.0
        uniforms.rimIntensity = 0.45

        // Void params
        uniforms.voidProgress = voidProgress
        uniforms.voidScale = 1.0

        // Disk params
        uniforms.diskRotation = time * 0.5 // Continuous rotation
        uniforms.diskOpacity = sendSceneActive ? 0.8 : 0.0

        // Ripple params
        if activeRipple {
            let elapsed = Float(CACurrentMediaTime() - rippleStartTime)
            uniforms.rippleProgress = clamp(elapsed / 0.95, 0, 1)
            uniforms.rippleCenter = rippleCenter
            uniforms.rippleMaxRadius = 0.32
        } else {
            uniforms.rippleProgress = 0
        }

        // Checkmark params
        if sendCompleted {
            uniforms.checkProgress = sendCheckmarkProgress
            uniforms.checkCenter = SIMD2<Float>(0.5, 0.5)
            uniforms.checkSize = 0.4
        } else {
            uniforms.checkProgress = 0
        }

        let ptr = uniformsBuffer.contents().bindMemory(to: MetaballUniforms.self, capacity: 1)
        ptr.pointee = uniforms

        let dropPtr = dropBuffer.contents().bindMemory(to: MetalDrop.self, capacity: maxDrops)
        for (i, drop) in allDrops.enumerated() {
            dropPtr[i] = drop.metalDrop
        }
        for i in allDrops.count..<maxDrops {
            dropPtr[i] = MetalDrop(pos: .zero, radius: 0, phase: 0, vy: 0, alive: 0, _pad: (0,0))
        }
    }

    // ──────────────────────────────────────────────────────────────
    // RENDER ENCODING (called from MetalView)
    // ──────────────────────────────────────────────────────────────

    func encodeComputePasses(commandBuffer: MTLCommandBuffer) {
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(width: (fieldWidth + 15) / 16,
                              height: (fieldHeight + 15) / 16, depth: 1)

        // Field solve
        computeEncoder.setComputePipelineState(fieldSolvePipeline)
        computeEncoder.setBuffer(dropBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(fieldBufferA, offset: 0, index: 1)
        computeEncoder.setBuffer(uniformsBuffer, offset: 0, index: 2)
        computeEncoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)

        // Blur H
        computeEncoder.setComputePipelineState(blurHPipeline)
        computeEncoder.setBuffer(fieldBufferA, offset: 0, index: 0)
        computeEncoder.setBuffer(fieldBufferB, offset: 0, index: 1)
        computeEncoder.setBuffer(uniformsBuffer, offset: 0, index: 2)
        computeEncoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)

        // Blur V
        computeEncoder.setComputePipelineState(blurVPipeline)
        computeEncoder.setBuffer(fieldBufferB, offset: 0, index: 0)
        computeEncoder.setBuffer(fieldBufferA, offset: 0, index: 1)
        computeEncoder.setBuffer(uniformsBuffer, offset: 0, index: 2)
        computeEncoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()

        // Copy field to texture
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        blitEncoder.copy(from: fieldBufferA, sourceOffset: 0,
                          sourceBytesPerRow: fieldWidth * 4,
                          sourceBytesPerImage: 0,
                          sourceSize: MTLSize(width: fieldWidth, height: fieldHeight, depth: 1),
                          to: fieldTextureA, destinationSlice: 0, destinationLevel: 0,
                          destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()

        // Normals
        let computeEncoder2 = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder2.setComputePipelineState(normalsPipeline)
        computeEncoder2.setBuffer(fieldBufferA, offset: 0, index: 0)
        computeEncoder2.setBuffer(normalsBuffer, offset: 0, index: 1)
        computeEncoder2.setBuffer(uniformsBuffer, offset: 0, index: 2)
        computeEncoder2.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder2.endEncoding()
    }

    func encodeRenderPasses(renderEncoder: MTLRenderCommandEncoder) {
        // Metaballs
        renderEncoder.setRenderPipelineState(metaballRenderPipeline)
        renderEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(fieldTextureA, index: 0)
        renderEncoder.setFragmentBuffer(normalsBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // Disk (rotating conic gradient) - only during send
        if sendSceneActive {
            renderEncoder.setRenderPipelineState(diskRenderPipeline)
            renderEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // Void/Black hole
        if voidProgress > 0.01 {
            renderEncoder.setRenderPipelineState(voidRenderPipeline)
            renderEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // Ripple
        if activeRipple {
            renderEncoder.setRenderPipelineState(rippleRenderPipeline)
            renderEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // Checkmark
        if sendCompleted && sendCheckmarkProgress > 0 {
            renderEncoder.setRenderPipelineState(checkmarkRenderPipeline)
            renderEncoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    // ──────────────────────────────────────────────────────────────
    // HELPERS
    // ──────────────────────────────────────────────────────────────

    private func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
        Swift.max(min, Swift.min(max, value))
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    private func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        length(a - b)
    }
}