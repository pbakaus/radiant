import ScreenSaver
import Metal
import QuartzCore
import CoreVideo

// MARK: - Constants

private let RESOLUTION_SCALE: CGFloat = 0.5
private let DWELL_S: Double = 12.0
private let MORPH_S: Double = 3.0
private let HUE_CYCLE_S: Float = 300.0
private let TIME_DIVISOR: Double = 4000.0

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

// MARK: - Screen Saver View

@objc(RadiantScreenSaverView)
class RadiantScreenSaverView: ScreenSaverView {

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var metalLayer: CAMetalLayer?
    private var uniformBuffer: MTLBuffer?
    // Blend-enabled pipelines: src * blendAlpha + dst * one
    // During dwell (alpha=1, clear): result = shader
    // During morph pass 1 (alpha=1-p, clear): result = shaderA * (1-p)
    // During morph pass 2 (alpha=p, load): result = shaderB*p + shaderA*(1-p)
    private var pipelines: [MTLRenderPipelineState] = []
    private var displayLink: CVDisplayLink?
    private var startTime: CFTimeInterval = 0
    private var frameCount = 0

    // Cycling
    private var shuffledOrder: [Int] = []
    private var seqIndex: Int = 0
    private var phaseStartTime: CFTimeInterval = 0
    private var isMorphing = false

    // MARK: - Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        self.animationTimeInterval = 1.0 / 60.0
        setupMetal()
        setupCycling()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.animationTimeInterval = 1.0 / 60.0
        setupMetal()
        setupCycling()
    }

    private func setupMetal() {
        startTime = CACurrentMediaTime()

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        self.device = device
        guard let queue = device.makeCommandQueue() else { return }
        self.commandQueue = queue

        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.displaySyncEnabled = true
        metalLayer.contentsGravity = .resize
        metalLayer.frame = self.bounds
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.wantsLayer = true
        self.layer = metalLayer
        self.metalLayer = metalLayer

        guard let library = loadShaderLibrary(device: device) else { return }
        guard let vertexFunc = library.makeFunction(name: "vs_fullscreen") else { return }

        // Create blend-enabled pipelines for cross-fade support
        for desc in shaderRegistry {
            guard let fragFunc = library.makeFunction(name: desc.fragmentFunction) else { continue }
            let pipeDesc = MTLRenderPipelineDescriptor()
            pipeDesc.vertexFunction = vertexFunc
            pipeDesc.fragmentFunction = fragFunc
            let attach = pipeDesc.colorAttachments[0]!
            attach.pixelFormat = .bgra8Unorm
            attach.isBlendingEnabled = true
            attach.sourceRGBBlendFactor = .blendAlpha      // src * blendColor.a
            attach.destinationRGBBlendFactor = .one         // dst * 1
            attach.rgbBlendOperation = .add
            attach.sourceAlphaBlendFactor = .blendAlpha
            attach.destinationAlphaBlendFactor = .one
            attach.alphaBlendOperation = .add
            if let pso = try? device.makeRenderPipelineState(descriptor: pipeDesc) {
                pipelines.append(pso)
            }
        }

        uniformBuffer = device.makeBuffer(length: 16, options: .storageModeShared)
    }

    private func loadShaderLibrary(device: MTLDevice) -> MTLLibrary? {
        let bundle = Bundle(for: type(of: self))
        if let libURL = bundle.url(forResource: "default", withExtension: "metallib") {
            return try? device.makeLibrary(URL: libURL)
        }
        return device.makeDefaultLibrary()
    }

    private func setupCycling() {
        let count = pipelines.count
        guard count > 0 else { return }
        shuffledOrder = Array(0..<count)
        for i in stride(from: count - 1, through: 1, by: -1) {
            shuffledOrder.swapAt(i, Int.random(in: 0...i))
        }
        seqIndex = 0
        phaseStartTime = CACurrentMediaTime()
    }

    // MARK: - Layout

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerSize()
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        updateLayerSize()
    }

    private func updateLayerSize() {
        guard let metalLayer = metalLayer else { return }
        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        metalLayer.frame = self.bounds
        let w = max(Int(self.bounds.width * scale * RESOLUTION_SCALE), 1)
        let h = max(Int(self.bounds.height * scale * RESOLUTION_SCALE), 1)
        metalLayer.drawableSize = CGSize(width: w, height: h)
    }

    // MARK: - Start / Stop

    override func startAnimation() {
        super.startAnimation()
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link = link else { return }
        CVDisplayLinkSetOutputCallback(link, displayLinkCallback,
            Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
        self.displayLink = link
    }

    override func stopAnimation() {
        if let link = displayLink { CVDisplayLinkStop(link); displayLink = nil }
        super.stopAnimation()
    }

    override func animateOneFrame() {}

    // MARK: - Render

    func renderFrame() {
        frameCount += 1
        guard let metalLayer = metalLayer,
              let commandQueue = commandQueue,
              let uniformBuffer = uniformBuffer,
              !pipelines.isEmpty else { return }

        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.frame = self.bounds
        metalLayer.contentsScale = scale
        let drawW = max(self.bounds.width * scale * RESOLUTION_SCALE, 1)
        let drawH = max(self.bounds.height * scale * RESOLUTION_SCALE, 1)
        metalLayer.drawableSize = CGSize(width: drawW, height: drawH)

        guard let drawable = metalLayer.nextDrawable() else { return }

        let now = CACurrentMediaTime()
        let timeSec = Float((now - startTime) * 1000.0 / TIME_DIVISOR)
        let phaseElapsed = now - phaseStartTime

        // State machine: seqIndex always points to the DISPLAYED shader.
        // Advance at morph START so the incoming shader becomes current for the next dwell.
        if isMorphing {
            if phaseElapsed >= MORPH_S {
                isMorphing = false
                phaseStartTime = now
            }
        } else {
            if phaseElapsed >= DWELL_S {
                isMorphing = true
                phaseStartTime = now
                seqIndex += 1 // advance here: outgoing = seqIndex-1, incoming = seqIndex
            }
        }

        let phaseNow = now - phaseStartTime

        // Fill uniforms
        let buf = uniformBuffer.contents().bindMemory(to: Float.self, capacity: 4)
        buf[0] = timeSec
        buf[1] = (timeSec / HUE_CYCLE_S) * Float.pi * 2
        buf[2] = Float(drawW)
        buf[3] = Float(drawH)

        let currentIdx = shuffledOrder[seqIndex % shuffledOrder.count]
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if isMorphing {
            let progress = Float(min(phaseNow / MORPH_S, 1.0))
            let outIdx = shuffledOrder[((seqIndex - 1) % shuffledOrder.count + shuffledOrder.count) % shuffledOrder.count]

            // Pass 1: outgoing shader at alpha = (1 - progress), clear first
            let passA = MTLRenderPassDescriptor()
            passA.colorAttachments[0].texture = drawable.texture
            passA.colorAttachments[0].loadAction = .clear
            passA.colorAttachments[0].storeAction = .store
            passA.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passA) {
                enc.setRenderPipelineState(pipelines[outIdx])
                enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                enc.setBlendColor(red: 1, green: 1, blue: 1, alpha: Float(1.0 - progress))
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }

            // Pass 2: incoming shader (= current for next dwell) at alpha = progress
            let passB = MTLRenderPassDescriptor()
            passB.colorAttachments[0].texture = drawable.texture
            passB.colorAttachments[0].loadAction = .load
            passB.colorAttachments[0].storeAction = .store

            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passB) {
                enc.setRenderPipelineState(pipelines[currentIdx])
                enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                enc.setBlendColor(red: 1, green: 1, blue: 1, alpha: progress)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        } else {
            // Dwell: single shader, alpha = 1.0
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)

            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                enc.setRenderPipelineState(pipelines[currentIdx])
                enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                enc.setBlendColor(red: 1, green: 1, blue: 1, alpha: 1.0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
    override func draw(_ rect: NSRect) {}
}
