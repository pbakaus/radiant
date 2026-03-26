import ScreenSaver
import Metal
import QuartzCore
import CoreVideo

// MARK: - Constants

private let RESOLUTION_SCALE: CGFloat = 0.5

// Cycling timing (matches zoom route)
private let DWELL_S: Double = 12.0
private let MORPH_S: Double = 3.0
private let ZOOM_MIN: Float = 1.0
private let ZOOM_MAX: Float = 1.35
private let HUE_CYCLE_S: Float = 300.0
private let TIME_DIVISOR: Double = 4000.0

// MARK: - File logging

private let logFile = NSHomeDirectory() + "/radiant-screensaver.log"

private func sslog(_ msg: String) {
    let ts = String(format: "%.3f", CACurrentMediaTime())
    let line = "[\(ts)] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let fh = FileHandle(forWritingAtPath: logFile) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
}

// MARK: - CVDisplayLink callback

private func displayLinkCallback(
    _ displayLink: CVDisplayLink,
    _ inNow: UnsafePointer<CVTimeStamp>,
    _ inOutputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ context: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let context = context else { return kCVReturnError }
    let view = Unmanaged<RadiantScreenSaverView>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { view.renderFrame() }
    return kCVReturnSuccess
}

// MARK: - Cycling state

private enum CyclePhase {
    case dwell
    case morph
}

// MARK: - Screen Saver View

@objc(RadiantScreenSaverView)
class RadiantScreenSaverView: ScreenSaverView {

    // Metal core
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var metalLayer: CAMetalLayer?
    private var uniformBuffer: MTLBuffer?

    // Per-shader render pipelines (indexed by shaderRegistry order)
    private var shaderPipelines: [MTLRenderPipelineState] = []
    // Transition pipeline
    private var transitionPipeline: MTLRenderPipelineState?
    // Transition uniform buffer
    private var transitionUniformBuffer: MTLBuffer?

    // Offscreen render targets for A/B compositing
    private var textureA: MTLTexture?
    private var textureB: MTLTexture?

    // CVDisplayLink
    private var displayLink: CVDisplayLink?

    // Timing
    private var startTime: CFTimeInterval = 0
    private var frameCount = 0

    // Cycling state
    private var shuffledOrder: [Int] = []
    private var seqIndex: Int = 0
    private var phase: CyclePhase = .dwell
    private var phaseStartTime: CFTimeInterval = 0

    // MARK: - Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        sslog("init frame=\(frame) isPreview=\(isPreview)")
        setupMetal()
        setupCycling()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
        setupCycling()
    }

    // MARK: - Metal setup

    private func setupMetal() {
        startTime = CACurrentMediaTime()

        guard let device = MTLCreateSystemDefaultDevice() else {
            sslog("No Metal device"); return
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            sslog("No command queue"); return
        }
        self.commandQueue = queue

        // Metal layer
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false // need to sample offscreen textures
        layer.displaySyncEnabled = true
        layer.contentsGravity = .resize // stretch half-res drawable to fill view
        layer.frame = self.bounds
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.wantsLayer = true
        self.layer = layer
        self.metalLayer = layer

        // Load shader library
        guard let library = loadShaderLibrary(device: device) else {
            sslog("No shader library"); return
        }

        // Shared vertex function
        guard let vertexFunc = library.makeFunction(name: "vs_fullscreen") else {
            sslog("No vs_fullscreen"); return
        }

        // Create per-shader pipelines
        for (i, desc) in shaderRegistry.enumerated() {
            guard let fragFunc = library.makeFunction(name: desc.fragmentFunction) else {
                sslog("Missing fragment function: \(desc.fragmentFunction)")
                continue
            }
            let pipeDesc = MTLRenderPipelineDescriptor()
            pipeDesc.vertexFunction = vertexFunc
            pipeDesc.fragmentFunction = fragFunc
            pipeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            do {
                let pso = try device.makeRenderPipelineState(descriptor: pipeDesc)
                shaderPipelines.append(pso)
                sslog("Pipeline[\(i)] \(desc.id) OK")
            } catch {
                sslog("Pipeline[\(i)] \(desc.id) FAILED: \(error)")
            }
        }

        // Transition pipeline
        if let transFragFunc = library.makeFunction(name: "fs_transition") {
            let pipeDesc = MTLRenderPipelineDescriptor()
            pipeDesc.vertexFunction = vertexFunc
            pipeDesc.fragmentFunction = transFragFunc
            pipeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            do {
                transitionPipeline = try device.makeRenderPipelineState(descriptor: pipeDesc)
                sslog("Transition pipeline OK")
            } catch {
                sslog("Transition pipeline FAILED: \(error)")
            }
        }

        // Common uniform buffer (16 bytes: time, hue_shift, resolution.xy)
        uniformBuffer = device.makeBuffer(length: 16, options: .storageModeShared)
        // Transition uniform buffer (24 bytes: progress, time, hue_shift, zoom, resolution.xy)
        transitionUniformBuffer = device.makeBuffer(length: 24, options: .storageModeShared)
    }

    private func loadShaderLibrary(device: MTLDevice) -> MTLLibrary? {
        let bundle = Bundle(for: type(of: self))
        if let libURL = bundle.url(forResource: "default", withExtension: "metallib") {
            do { return try device.makeLibrary(URL: libURL) }
            catch { sslog("metallib failed: \(error)") }
        }
        // Fallback: try runtime compilation of bundled source files
        // (individual .metal files won't work here — need the metallib)
        return device.makeDefaultLibrary()
    }

    // MARK: - Offscreen textures

    private func ensureOffscreenTextures(width: Int, height: Int) {
        guard let device = device else { return }
        if let existing = textureA, existing.width == width, existing.height == height { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(width, 1),
            height: max(height, 1),
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        textureA = device.makeTexture(descriptor: desc)
        textureB = device.makeTexture(descriptor: desc)
        sslog("Offscreen textures: \(width)x\(height)")
    }

    // MARK: - Cycling

    private func setupCycling() {
        let count = shaderRegistry.count
        shuffledOrder = Array(0..<count)
        // Fisher-Yates shuffle
        for i in stride(from: count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            shuffledOrder.swapAt(i, j)
        }
        seqIndex = 0
        phase = .dwell
        phaseStartTime = CACurrentMediaTime()
    }

    private var currentShaderIndex: Int {
        guard !shuffledOrder.isEmpty else { return 0 }
        return shuffledOrder[seqIndex % shuffledOrder.count]
    }

    private var nextShaderIndex: Int {
        guard !shuffledOrder.isEmpty else { return 0 }
        return shuffledOrder[(seqIndex + 1) % shuffledOrder.count]
    }

    // MARK: - Start / Stop

    override func startAnimation() {
        super.startAnimation()
        startDisplayLink()
    }

    override func stopAnimation() {
        stopDisplayLink()
        super.stopAnimation()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link = link else { sslog("No CVDisplayLink"); return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, displayLinkCallback, selfPtr)
        CVDisplayLinkStart(link)
        self.displayLink = link
        sslog("CVDisplayLink started")
    }

    private func stopDisplayLink() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
    }

    override func animateOneFrame() {} // CVDisplayLink drives rendering

    // MARK: - Render

    func renderFrame() {
        frameCount += 1

        guard let metalLayer = metalLayer,
              let commandQueue = commandQueue,
              let uniformBuffer = uniformBuffer,
              let transitionUniformBuffer = transitionUniformBuffer,
              let transitionPipeline = transitionPipeline else { return }

        // Update layer size
        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.frame = self.bounds
        metalLayer.contentsScale = scale
        let drawW = max(Int(self.bounds.width * scale * RESOLUTION_SCALE), 1)
        let drawH = max(Int(self.bounds.height * scale * RESOLUTION_SCALE), 1)
        metalLayer.drawableSize = CGSize(width: drawW, height: drawH)

        ensureOffscreenTextures(width: drawW, height: drawH)

        guard let drawable = metalLayer.nextDrawable() else { return }
        guard self.textureA != nil, self.textureB != nil else { return }

        let now = CACurrentMediaTime()
        let elapsedMs = (now - startTime) * 1000.0
        let timeSec = Float(elapsedMs / TIME_DIVISOR)
        let phaseElapsed = now - phaseStartTime

        // ── Update cycling state machine ──
        switch phase {
        case .dwell:
            if phaseElapsed >= DWELL_S {
                phase = .morph
                phaseStartTime = now
            }
        case .morph:
            if phaseElapsed >= MORPH_S {
                seqIndex += 1
                // Swap textures: B (fully revealed) becomes A for seamless dwell start
                swap(&self.textureA, &self.textureB)
                phase = .dwell
                phaseStartTime = now
            }
        }

        // Re-read after potential swap
        guard let texA = self.textureA, let texB = self.textureB else { return }

        // ── Fill common uniforms ──
        let buf = uniformBuffer.contents().bindMemory(to: Float.self, capacity: 4)
        buf[0] = timeSec
        buf[1] = (timeSec / HUE_CYCLE_S) * Float.pi * 2
        buf[2] = Float(drawW)
        buf[3] = Float(drawH)

        // ── Compute phase progress and zoom ──
        let progress: Float
        let zoom: Float
        let isMorphing = (phase == .morph)

        if isMorphing {
            let morphProgress = Float(min(phaseElapsed / MORPH_S, 1.0))
            progress = morphProgress
            zoom = ZOOM_MAX - (ZOOM_MAX - ZOOM_MIN) * morphProgress
        } else {
            progress = 0.0
            let dwellProgress = Float(min(phaseElapsed / DWELL_S, 1.0))
            zoom = ZOOM_MIN + (ZOOM_MAX - ZOOM_MIN) * dwellProgress
        }

        // ── Fill transition uniforms ──
        let tbuf = transitionUniformBuffer.contents().bindMemory(to: Float.self, capacity: 6)
        tbuf[0] = progress
        tbuf[1] = timeSec
        tbuf[2] = (timeSec / HUE_CYCLE_S) * Float.pi * 2
        tbuf[3] = zoom
        tbuf[4] = Float(drawW)
        tbuf[5] = Float(drawH)

        let currentIdx = currentShaderIndex
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if isMorphing {
            // ── MORPH: render both shaders to offscreen, composite to drawable ──

            // Pass 1: current → textureA
            if currentIdx < shaderPipelines.count {
                let passA = MTLRenderPassDescriptor()
                passA.colorAttachments[0].texture = texA
                passA.colorAttachments[0].loadAction = .clear
                passA.colorAttachments[0].storeAction = .store
                passA.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0)

                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passA) {
                    enc.setRenderPipelineState(shaderPipelines[currentIdx])
                    enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    enc.endEncoding()
                }
            }

            // Pass 2: next → textureB
            let nextIdx = nextShaderIndex
            if nextIdx < shaderPipelines.count {
                let passB = MTLRenderPassDescriptor()
                passB.colorAttachments[0].texture = texB
                passB.colorAttachments[0].loadAction = .clear
                passB.colorAttachments[0].storeAction = .store
                passB.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0)

                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passB) {
                    enc.setRenderPipelineState(shaderPipelines[nextIdx])
                    enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    enc.endEncoding()
                }
            }

            // Pass 3: composite → drawable
            let passC = MTLRenderPassDescriptor()
            passC.colorAttachments[0].texture = drawable.texture
            passC.colorAttachments[0].loadAction = .dontCare
            passC.colorAttachments[0].storeAction = .store

            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passC) {
                enc.setRenderPipelineState(transitionPipeline)
                enc.setFragmentBuffer(transitionUniformBuffer, offset: 0, index: 0)
                enc.setFragmentTexture(texA, index: 0)
                enc.setFragmentTexture(texB, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        } else {
            // ── DWELL: render directly to drawable — single pass, no offscreen ──
            if currentIdx < shaderPipelines.count {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = drawable.texture
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0)

                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                    enc.setRenderPipelineState(shaderPipelines[currentIdx])
                    enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    enc.endEncoding()
                }
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        if frameCount <= 3 || frameCount % 300 == 0 {
            sslog("frame=\(frameCount) phase=\(phase) drawSize=\(drawW)x\(drawH)")
        }
    }

    // MARK: - Layout

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    override func draw(_ rect: NSRect) {}
}
